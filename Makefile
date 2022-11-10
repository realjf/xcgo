

build:
	@echo 'build docker...'
	@sudo docker build --network host -t realjf/xcgo-sdk11.3-catalina:go1.19  --build-arg OSX_VERSION_MIN=10.9 \
	--build-arg OSX_SDK=MacOSX11.3.sdk .


push:
	@echo 'git push...'
	@git add -A && git commit -m "update" && git push origin master

clean_docker_image:
	@docker system prune -a