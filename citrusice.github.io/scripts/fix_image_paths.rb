#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
# 图片路径修复脚本 - 修复已有的图片路径问题

require 'fileutils'
require 'cgi'

# 配置
POST_DIR = '_posts'
IMAGE_DIR = 'assets/images'
IMAGE_PATTERN = /!\[(.*?)\]\(\/assets\/images\/([^)]+)\)/

# 确保图片目录存在
FileUtils.mkdir_p(IMAGE_DIR)

# 处理单个文件
def process_file(file_path)
  puts "处理文件: #{file_path}"
  content = File.read(file_path)
  modified = false
  
  # 查找所有图片链接
  content.gsub!(IMAGE_PATTERN) do |match|
    alt_text = $1
    image_filename = $2
    
    # 解码文件名
    decoded_filename = CGI.unescape(image_filename)
    
    # 清理文件名，移除特殊字符
    sanitized = decoded_filename.gsub(/[^a-zA-Z0-9\.\-_]/, '_')
    clean_filename = sanitized.empty? ? "image.png" : sanitized
    
    # 构建新的本地路径
    local_path = File.join(IMAGE_DIR, clean_filename)
    
    # 检查原始图片是否存在
    original_path = File.join(IMAGE_DIR, image_filename)
    if File.exist?(original_path)
      # 获取绝对路径，用于比较
      abs_original_path = File.absolute_path(original_path)
      abs_local_path = File.absolute_path(local_path)
      
      # 如果原始图片存在但文件名不同，复制它
      if abs_original_path != abs_local_path
        puts "  复制图片: #{original_path} -> #{local_path}"
        begin
          FileUtils.cp(original_path, local_path)
          modified = true
        rescue ArgumentError => e
          puts "  警告: 无法复制文件: #{e.message}"
        end
      else
        puts "  图片路径相同，无需复制: #{original_path}"
      end
    else
      puts "  警告: 图片不存在: #{original_path}"
    end
    
    # 返回更新后的Markdown图片链接
    "![#{alt_text}](/#{local_path})"
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
  puts "修复所有文章中的图片路径..."
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