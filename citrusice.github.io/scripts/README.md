# Jekyll 图片本地化插件

这个插件会在 Jekyll 构建过程中自动下载文章中引用的远程图片，并将它们保存到本地，然后更新文章中的链接指向本地路径。

## 功能

- 自动下载文章和页面中的远程图片
- 将图片保存到本地指定目录
- 更新 Markdown 文件中的图片链接
- 支持配置跳过特定的 URL 模式
- 在构建过程中自动运行，无需手动干预

## 使用方法

插件已经集成到 Jekyll 构建流程中，每次运行 `jekyll build` 或 `jekyll serve` 时会自动处理图片。

### 配置选项

在 `_config.yml` 中可以自定义插件的行为：

```yaml
# 图片本地化插件配置
image_localizer:
  enabled: true                # 是否启用插件
  image_dir: 'assets/images'   # 图片保存目录
  process_pages: true          # 是否处理页面
  process_posts: true          # 是否处理文章
  skip_patterns:               # 跳过的URL模式（正则表达式）
    - '^data:'                 # 跳过 data URL
```

### 手动处理图片

如果需要手动处理图片，可以使用 `scripts/image_downloader.rb` 脚本：

```bash
# 处理单个文件
ruby scripts/image_downloader.rb _posts/2022-10-23-example-post.markdown

# 处理最新的文章
ruby scripts/image_downloader.rb
```

## 工作原理

1. 插件在 Jekyll 读取站点内容后、渲染前运行
2. 它会扫描所有 Markdown 文件中的图片链接 `![alt](http://example.com/image.jpg)`
3. 对于每个远程图片链接，插件会：
   - 下载图片到本地 `assets/images` 目录
   - 更新 Markdown 文件中的链接指向本地路径
4. 更新后的链接格式为 `![alt](/assets/images/image.jpg)`

## 注意事项

- 插件会修改原始 Markdown 文件，建议在使用前备份文件
- 如果图片下载失败，原始链接将保持不变
- 插件只处理 Markdown 文件中的图片链接，不处理 HTML 中的图片
- 对于没有明确文件名的 URL，插件会使用 URL 的 MD5 哈希作为文件名 