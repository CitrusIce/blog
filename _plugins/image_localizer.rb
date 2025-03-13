require 'fileutils'
require 'open-uri'
require 'uri'
require 'digest'
require 'cgi'
require 'pathname'

# Jekyll 图片本地化插件
# 在构建时自动下载文章中的远程图片并保存到本地
module Jekyll
  class ImageLocalizer
    # 图片匹配正则表达式 - 匹配远程图片
    IMAGE_PATTERN = /!\[(.*?)\]\((https?:\/\/[^)]+)\)/
    
    # 图片匹配正则表达式 - 匹配本地图片（相对路径）
    LOCAL_IMAGE_PATTERN = /!\[(.*?)\]\(\/assets\/images\/([^)]+)\)/
    
    # 图片匹配正则表达式 - 匹配所有图片链接（用于提取并判断是否为绝对路径）
    ALL_IMAGE_PATTERN = /!\[(.*?)\]\(([^)]+)\)/
    
    # 支持的图片扩展名
    IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .gif .webp .PNG .JPG .JPEG .GIF .WEBP]
    
    # 默认配置
    DEFAULT_CONFIG = {
      'enabled' => true,                # 是否启用插件
      'image_dir' => 'assets/images',   # 图片保存目录
      'process_pages' => true,          # 是否处理页面
      'process_posts' => true,          # 是否处理文章
      'skip_patterns' => [],            # 跳过的URL模式（正则表达式）
      'fix_existing_paths' => true,     # 是否修复已存在的本地图片路径
      'copy_local_images' => true       # 是否复制本地绝对路径的图片
    }
    
    def initialize(site)
      @site = site
      
      # 合并配置
      @config = DEFAULT_CONFIG.merge(site.config['image_localizer'] || {})
      
      # 如果插件被禁用，直接返回
      return unless @config['enabled']
      
      # 确保图片目录存在
      @image_dir = @config['image_dir']
      FileUtils.mkdir_p(File.join(@site.source, @image_dir))
      
      # 编译跳过模式
      @skip_patterns = @config['skip_patterns'].map { |pattern| Regexp.new(pattern) }
      
      # 存储已下载的图片
      @downloaded_images = {}
      
      # 存储已复制的本地图片
      @copied_local_images = {}
    end
    
    # 处理所有文档
    def process_documents
      # 如果插件被禁用，直接返回
      return unless @config['enabled']
      
      # 处理文章
      if @config['process_posts']
        @site.posts.docs.each do |post|
          process_document(post)
        end
      end
      
      # 处理页面
      if @config['process_pages']
        @site.pages.each do |page|
          if page.ext =~ /\.(md|markdown)$/i
            process_document(page)
          end
        end
      end
      
      # 将下载的图片添加到静态文件列表
      add_static_files
    end
    
    # 处理单个文档
    def process_document(doc)
      # 读取原始文件内容
      file_path = doc.path
      return unless File.exist?(file_path)
      
      original_content = File.read(file_path)
      modified_content = process_content(original_content, file_path)
      
      # 如果内容被修改，写回文件
      if original_content != modified_content
        File.write(file_path, modified_content)
        Jekyll.logger.info "ImageLocalizer:", "已更新文件中的图片链接: #{file_path}"
        
        # 更新文档内容，确保Jekyll使用更新后的内容
        if doc.respond_to?(:content=)
          doc.content = modified_content
        end
      end
    end
    
    # 处理内容
    def process_content(content, file_path)
      modified_content = content.dup
      
      # 处理所有图片链接（包括远程URL和本地路径）
      modified_content = process_all_images(modified_content, file_path)
      
      modified_content
    end
    
    # 处理所有图片链接
    def process_all_images(content, file_path)
      # 查找所有图片链接
      content.gsub(ALL_IMAGE_PATTERN) do |match|
        alt_text = $1
        image_path = $2
        
        # 如果已经是assets/images下的图片，跳过
        if image_path =~ /^\/assets\/images\//
          Jekyll.logger.debug "ImageLocalizer:", "图片已在assets目录下: #{image_path}"
          next match
        end
        
        # 处理远程URL
        if image_path =~ /^https?:\/\//
          # 检查是否应该跳过此URL
          if should_skip_url?(image_path)
            Jekyll.logger.debug "ImageLocalizer:", "跳过图片: #{image_path}"
            next match
          end
          
          # 下载图片并获取本地路径
          local_path = download_image(image_path)
          
          if local_path
            # 返回更新后的Markdown图片链接
            relative_path = calculate_relative_path(file_path, local_path)
            "![#{alt_text}](#{relative_path})"
          else
            # 如果下载失败，保留原始链接
            match
          end
        else
          # 处理本地路径
          # 标准化路径（处理Windows和Unix路径差异）
          normalized_path = image_path.gsub('\\', '/')
          
          # 如果是相对路径，尝试解析
          if !normalized_path.start_with?('/') && !normalized_path.start_with?('C:/')
            # 相对路径，检查是否是图片
            if has_image_extension?(normalized_path)
              # 尝试从当前文件所在目录解析相对路径
              base_dir = File.dirname(file_path)
              full_path = File.join(base_dir, normalized_path)
              
              if File.exist?(full_path)
                # 复制图片并获取本地路径
                local_path = copy_local_image(full_path)
                
                if local_path
                  # 计算从当前文件到图片的相对路径
                  relative_path = calculate_relative_path(file_path, local_path)
                  next "![#{alt_text}](#{relative_path})"
                end
              end
            end
            next match
          end
          
          # 处理绝对路径
          # 如果不是图片文件，跳过
          next match unless has_image_extension?(normalized_path)
          
          # 复制图片并获取本地路径
          local_path = copy_local_image(normalized_path)
          
          if local_path
            # 计算从当前文件到图片的相对路径
            relative_path = calculate_relative_path(file_path, local_path)
            "![#{alt_text}](#{relative_path})"
          else
            # 如果复制失败，尝试Windows路径格式
            if normalized_path.start_with?('C:/')
              windows_path = normalized_path.gsub('/', '\\')
              local_path = copy_local_image(windows_path)
              
              if local_path
                # 计算从当前文件到图片的相对路径
                relative_path = calculate_relative_path(file_path, local_path)
                return "![#{alt_text}](#{relative_path})"
              end
            end
            
            # 如果仍然失败，保留原始链接
            Jekyll.logger.warn "ImageLocalizer:", "无法复制本地图片: #{normalized_path}"
            match
          end
        end
      end
    end
    
    # 判断文件是否为图片（根据扩展名）
    def has_image_extension?(file_path)
      ext = File.extname(file_path).downcase
      IMAGE_EXTENSIONS.include?(ext.downcase)
    end
    
    # 复制本地图片并返回本地路径
    def copy_local_image(image_path)
      # 如果已经复制过，直接返回本地路径
      return @copied_local_images[image_path] if @copied_local_images[image_path]
      
      # 检查图片是否存在
      unless File.exist?(image_path)
        Jekyll.logger.warn "ImageLocalizer:", "本地图片不存在: #{image_path}"
        return nil
      end
      
      # 生成文件名
      filename = File.basename(image_path)
      
      # 清理文件名，移除特殊字符
      clean_filename = sanitize_filename(filename)
      
      # 如果文件名为空，使用MD5哈希
      if clean_filename.empty?
        ext = File.extname(image_path).downcase
        ext = ext.empty? ? '.png' : ext
        clean_filename = "#{Digest::MD5.hexdigest(image_path)}#{ext}"
      end
      
      # 构建目标路径
      local_path = File.join(@image_dir, clean_filename)
      absolute_path = File.join(@site.source, local_path)
      
      # 复制图片
      begin
        Jekyll.logger.info "ImageLocalizer:", "复制本地图片: #{image_path} -> #{local_path}"
        FileUtils.cp(image_path, absolute_path)
      rescue => e
        Jekyll.logger.error "ImageLocalizer:", "复制失败: #{e.message}"
        return nil
      end
      
      # 存储已复制的图片
      @copied_local_images[image_path] = local_path
      
      local_path
    end
    
    # 计算从文件到图片的相对路径
    def calculate_relative_path(file_path, image_path)
      # 获取文件所在目录
      file_dir = File.dirname(file_path)
      file_dir_relative = file_dir.sub(@site.source + '/', '')
      
      # 计算相对路径
      if file_dir_relative.start_with?('_posts')
        # 对于文章，使用站点根目录相对路径
        "/#{image_path}"
      else
        # 对于其他页面，计算实际相对路径
        depth = file_dir_relative.count('/')
        prefix = '../' * depth
        "#{prefix}#{image_path}"
      end
    end
    
    # 下载图片并返回本地路径
    def download_image(image_url)
      # 如果已经下载过，直接返回本地路径
      return @downloaded_images[image_url] if @downloaded_images[image_url]
      
      # 解码URL
      decoded_url = CGI.unescape(image_url)
      
      # 生成本地文件名 (使用URL的最后部分或MD5哈希)
      original_filename = File.basename(URI.parse(decoded_url).path)
      
      # 清理文件名，移除特殊字符
      clean_filename = sanitize_filename(original_filename)
      
      if clean_filename.empty? || clean_filename == '/' || !has_image_extension?(clean_filename)
        # 如果URL没有明确的文件名或扩展名，使用URL的MD5哈希作为文件名
        ext = decoded_url.match(/\.(png|jpg|jpeg|gif|webp)($|\?)/i)
        ext = ext ? ext[1] : 'png'
        clean_filename = "#{Digest::MD5.hexdigest(decoded_url)}.#{ext}"
      end
      
      local_path = File.join(@image_dir, clean_filename)
      absolute_path = File.join(@site.source, local_path)
      
      # 如果图片不存在，下载它
      unless File.exist?(absolute_path)
        begin
          Jekyll.logger.info "ImageLocalizer:", "下载图片: #{image_url} -> #{local_path}"
          File.open(absolute_path, 'wb') do |file|
            file.write URI.open(image_url).read
          end
        rescue => e
          Jekyll.logger.error "ImageLocalizer:", "下载失败: #{e.message}"
          return nil
        end
      end
      
      # 存储已下载的图片
      @downloaded_images[image_url] = local_path
      
      local_path
    end
    
    # 清理文件名，移除特殊字符
    def sanitize_filename(filename)
      # 解码URL编码的文件名
      decoded = CGI.unescape(filename)
      
      # 移除不安全的字符，只保留字母、数字、点、连字符和下划线
      sanitized = decoded.gsub(/[^a-zA-Z0-9\.\-_]/, '_')
      
      # 确保文件名不为空
      sanitized.empty? ? "image.png" : sanitized
    end
    
    # 将下载的图片添加到静态文件列表
    def add_static_files
      # 添加下载的图片
      @downloaded_images.each_value do |local_path|
        add_static_file(local_path)
      end
      
      # 添加复制的本地图片
      @copied_local_images.each_value do |local_path|
        add_static_file(local_path)
      end
    end
    
    # 添加静态文件
    def add_static_file(local_path)
      # 获取相对路径
      dir = File.dirname(local_path)
      name = File.basename(local_path)
      
      # 创建静态文件对象
      static_file = Jekyll::StaticFile.new(
        @site,
        @site.source,
        dir,
        name
      )
      
      # 添加到站点的静态文件列表中
      @site.static_files << static_file
    end
    
    # 检查是否应该跳过此URL
    def should_skip_url?(url)
      @skip_patterns.any? { |pattern| url =~ pattern }
    end
  end
  
  # 注册构建钩子 - 在读取站点后，渲染前处理
  Hooks.register :site, :post_read do |site|
    # 检查配置
    config = site.config['image_localizer'] || {}
    enabled = config.fetch('enabled', true)
    
    if enabled
      Jekyll.logger.info "ImageLocalizer:", "开始处理文档中的图片..."
      localizer = ImageLocalizer.new(site)
      localizer.process_documents
      Jekyll.logger.info "ImageLocalizer:", "图片处理完成"
    else
      Jekyll.logger.info "ImageLocalizer:", "插件已禁用"
    end
  end
  
  # 注册Liquid标签，用于替换图片URL
  class ImageTag < Liquid::Tag
    def initialize(tag_name, markup, tokens)
      super
      @markup = markup.strip
    end
    
    def render(context)
      site = context.registers[:site]
      
      # 获取图片本地化器
      localizer = site.data['image_localizer']
      return @markup unless localizer
      
      # 替换图片URL
      if @markup =~ /^(https?:\/\/[^\s]+)$/
        image_url = $1
        local_path = localizer[image_url]
        return local_path ? "/#{local_path}" : image_url
      end
      
      @markup
    end
  end
end

# 注册Liquid标签
Liquid::Template.register_tag('img_url', Jekyll::ImageTag) 