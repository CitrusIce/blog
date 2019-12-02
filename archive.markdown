---
# Feel free to add content and custom Front Matter to this file.
# To modify the layout, see https://jekyllrb.com/docs/themes/#overriding-theme-defaults

layout: page
---
<ul>
  {% for post in site.posts %}
    <li>
    <span>
      <time datetime="{{ post.date | date_to_xmlschema }}">{{ post.date | date: "%Y-%m-%d" }}</time>
    </span>
    <span>
      <a class="post-link" href="{{ post.url }}"><h2 class="post-title">{{ post.title }}</h2></a>
    </span>
    </li>
  {% endfor %}
</ul>
