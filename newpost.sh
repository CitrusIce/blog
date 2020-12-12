filename="$(date "+%Y-%m-%d")-$1.markdown"
str=" ---\nlayout: post\ntitle:  \"\"\ndate:   $(date "+%Y-%m-%d %H:%M:%S +0800")\ncategories: \n---\n"
a=$(date "+%Y-%m-%d %H:%M:%S +0800")
echo -e $str 
echo -e $filename
echo -e $str >_posts/$filename
