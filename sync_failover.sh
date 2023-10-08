#!/bin/bash
FAILOVER_SERVER_IP='nginx2.example.local'
FAILOVER_SERVER_SSH_USER='root'
FAILOVER_SERVER_SSH_KEY='/root/.ssh/nginx2'
ERROR_EMAIL=email@example.com

function check_local_nginx_config(){
	echo "Checking the local nginx config"
	nginx -t >/dev/null
}

function execute_remote_command(){
	ssh $FAILOVER_SERVER_SSH_USER@$FAILOVER_SERVER_IP -i $FAILOVER_SERVER_SSH_KEY $1 >/dev/null
}

function send_error_email(){
	echo "There was an error whilst syncing remote nginx from $(hostname)" | mail -s "nginx sync error on $(hostname)" $ERROR_EMAIL --append="FROM:error@$(hostname)"
}

function check_package_installed(){
	which $1 >/dev/null
	if [ $? -ne 0 ]; then
		echo "$1 is not installed."
		echo "Terminating."
		exit 1
	fi
}


function check_remote_nginx_state(){
	echo "Checking the state of the remote nginx server"
	execute_remote_command "service nginx status" >/dev/null
	if [ $? -eq 0 ]; then
		echo "The remote nginx server is running"
		echo ""
	else
		echo "The remote nginx server has been stopped or has failed"
		send_error_email
		echo ""
	fi
}

function start_sync(){

	check_package_installed "rsync"

	check_local_nginx_config
	if [ $? -eq 0 ]; then
		echo ""
		echo "Syncing remote nginx server"
		rsync -rl -e "ssh -i $FAILOVER_SERVER_SSH_KEY" /etc/nginx $FAILOVER_SERVER_SSH_USER@$FAILOVER_SERVER_IP:/etc >/dev/null
		rsync -rl -e "ssh -i $FAILOVER_SERVER_SSH_KEY" /var/www $FAILOVER_SERVER_SSH_USER@$FAILOVER_SERVER_IP:/var >/dev/null
	else
		echo ""
		echo "The local nginx config is invalid - Terminating"
		send_error_email
		exit 1
	fi

	echo "Checking Nginx Config on Failover Server"
	execute_remote_command "nginx -t"
	if [ $? -eq 0 ]; then

		execute_remote_command "service nginx restart"
		if [ $? -eq 0   ] ; then
			echo "The remote nginx server has been restarted successfully"
			echo ""
			check_remote_nginx_state
			if [ $? -eq 0 ]; then
				exit 0
			else
				send_error_email
				exit 1
			fi
		else
			echo "There was a problem restarting the remote nginx server"
			echo "Terminating"
			send_error_email
			exit 1
		fi

	else
		echo ""
		echo "There is an error in the remote nginx servers config"
		echo "Check the remote nginx server"
		echo "Terminating"
		send_error_email
		(exit 1)
	fi

}

start_sync
