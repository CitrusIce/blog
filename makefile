all: build serve
.PHONY:initial
initial:
	git remote add citrusice.github.io git@github.com:CitrusIce/citrusice.github.io.git 
	git subtree add --prefix=citrusice.github.io citrusice.github.io master
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
