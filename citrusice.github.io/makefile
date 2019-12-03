all: build serve
<<<<<<< HEAD
<<<<<<< HEAD
=======
=======
>>>>>>> 3b974d48684ba69c9ca1278d86edbc81e739fee0
.PHONY:initial
initial:
	git remote add citrusice.github.io git@github.com:CitrusIce/citrusice.github.io.git 
	git subtree add --prefix=citrusice.github.io citrusice.github.io master
<<<<<<< HEAD
>>>>>>> c9eef7da491926f970ef515bc465cc6cd081d1ba
=======
>>>>>>> 3b974d48684ba69c9ca1278d86edbc81e739fee0
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
