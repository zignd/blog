run:
	hugo server
deploy:
	hugo
	sudo rm -rf /var/www/html
	sudo mv public/* /var/www/html
