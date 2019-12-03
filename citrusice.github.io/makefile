all: build serve
<<<<<<< HEAD
=======
.PHONY:initial
initial:
	git remote add citrusice.github.io git@github.com:CitrusIce/citrusice.github.io.git 
	git subtree add --prefix=citrusice.github.io citrusice.github.io master
>>>>>>> c9eef7da491926f970ef515bc465cc6cd081d1ba
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
