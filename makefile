all: build serve
.PHONY:serve
serve:
	bundle exec jekyll serve -d citrusice.github.io
.PHONY:build
build:
	bundle exec jekyll build -d citrusice.github.io
.PHONY:push
push:
	git push
	git subtree push --prefix=citrusice.github.io git@github.com:CitrusIce/citrusice.github.io.git master
