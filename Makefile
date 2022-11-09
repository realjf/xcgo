

build:
	@echo 'build docker...'
	@docker build -t realjf/xcgo:go1.19 .


push:
	@echo 'git push...'
	@git add -A && git commit -m "update" && git push origin master

clean_docker_image:
	@docker system prune -a