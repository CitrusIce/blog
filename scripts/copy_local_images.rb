#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
# 本地图片复制脚本 - 复制本地绝对路径的图片到assets/images目录

require 'fileutils'
require 'cgi'
require 'digest'
require 'pathname'
require 'open-uri'
require 'uri'

# 配置
POST_DIR = '_posts'
IMAGE_DIR = 'assets/images'
# 匹配所有图片链接
ALL_IMAGE_PATTERN = /!\[(.*?)\]\(([^)]+)\)/

# 支持的图片扩展名
IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .gif .webp .PNG .JPG .JPEG .GIF .WEBP]

# 确保图片目录存在
FileUtils.mkdir_p(IMAGE_DIR)

# 判断文件是否为图片（根据扩展名）
def has_image_extension?(file_path)
  ext = File.extname(file_path).downcase
  IMAGE_EXTENSIONS.include?(ext)
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

# 下载远程图片
def download_image(image_url)
  puts "  下载远程图片: #{image_url}"
  
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
  
  local_path = File.join(IMAGE_DIR, clean_filename)
  
  # 如果图片不存在，下载它
  unless File.exist?(local_path)
    begin
      puts "  下载图片: #{image_url} -> #{local_path}"
      File.open(local_path, 'wb') do |file|
        file.write URI.open(image_url).read
      end
      return local_path
    rescue => e
      puts "  警告: 下载失败: #{e.message}"
      return nil
    end
  else
    puts "  图片已存在: #{local_path}"
    return local_path
  end
end

# 处理单个文件
def process_file(file_path)
  puts "处理文件: #{file_path}"
  content = File.read(file_path)
  modified = false
  
  # 查找所有图片链接
  content.gsub!(ALL_IMAGE_PATTERN) do |match|
    alt_text = $1
    image_path = $2
    
    # 如果已经是assets/images下的图片，跳过
    if image_path =~ /^\/assets\/images\//
      puts "  图片已在assets目录下: #{image_path}"
      next match
    end
    
    # 处理远程URL
    if image_path =~ /^https?:\/\//
      local_path = download_image(image_path)
      if local_path
        modified = true
        next "![#{alt_text}](/#{local_path})"
      else
        next match
      end
    end
    
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
          # 生成文件名
          filename = File.basename(full_path)
          
          # 清理文件名，移除特殊字符
          clean_filename = sanitize_filename(filename)
          
          # 构建目标路径
          local_path = File.join(IMAGE_DIR, clean_filename)
          
          # 复制图片
          begin
            puts "  复制相对路径图片: #{full_path} -> #{local_path}"
            FileUtils.cp(full_path, local_path)
            modified = true
            next "![#{alt_text}](/#{local_path})"
          rescue => e
            puts "  警告: 无法复制文件: #{e.message}"
          end
        end
      end
      next match
    end
    
    # 处理绝对路径
    # 如果不是图片文件，跳过
    next match unless has_image_extension?(normalized_path)
    
    # 检查图片是否存在
    if File.exist?(normalized_path)
      # 生成文件名
      filename = File.basename(normalized_path)
      
      # 清理文件名，移除特殊字符
      clean_filename = sanitize_filename(filename)
      
      # 构建目标路径
      local_path = File.join(IMAGE_DIR, clean_filename)
      
      # 复制图片
      begin
        puts "  复制图片: #{normalized_path} -> #{local_path}"
        FileUtils.cp(normalized_path, local_path)
        modified = true
      rescue => e
        puts "  警告: 无法复制文件: #{e.message}"
        next match
      end
      
      # 返回更新后的Markdown图片链接
      "![#{alt_text}](/#{local_path})"
    else
      puts "  警告: 图片不存在: #{normalized_path}"
      # 尝试处理Windows路径
      if normalized_path.start_with?('C:/')
        # 尝试转换为Windows格式路径
        windows_path = normalized_path.gsub('/', '\\')
        if File.exist?(windows_path)
          # 生成文件名
          filename = File.basename(windows_path)
          
          # 清理文件名，移除特殊字符
          clean_filename = sanitize_filename(filename)
          
          # 构建目标路径
          local_path = File.join(IMAGE_DIR, clean_filename)
          
          # 复制图片
          begin
            puts "  复制图片: #{windows_path} -> #{local_path}"
            FileUtils.cp(windows_path, local_path)
            modified = true
            return "![#{alt_text}](/#{local_path})"
          rescue => e
            puts "  警告: 无法复制文件: #{e.message}"
          end
        end
      end
      match
    end
  end
  
  # 如果内容被修改，保存文件
  if modified
    File.write(file_path, content)
    puts "  文件已更新: #{file_path}"
  else
    puts "  文件未修改: #{file_path}"
  end
end

# 处理所有文章
def process_all_posts
  posts = Dir.glob(File.join(POST_DIR, '*.{markdown,md}'))
  
  if posts.empty?
    puts "未找到任何文章"
  else
    puts "找到 #{posts.size} 篇文章"
    
    # 处理每篇文章
    posts.each do |post|
      process_file(post)
    end
    
    puts "所有文章处理完成"
  end
end

# 主程序
if ARGV.empty?
  puts "复制所有文章中的本地图片..."
  process_all_posts
else
  # 处理指定的文件
  ARGV.each do |file_path|
    if File.exist?(file_path)
      process_file(file_path)
    else
      puts "文件不存在: #{file_path}"
    end
  end
end 