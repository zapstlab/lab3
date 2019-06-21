#!/bin/bash

set -e

port=$(ctx node properties port)

ctx logger info "Starting HTTP server on port ${port}"

ctx logger info "Waiting for server to launch on port ${port}"
url="http://localhost:${port}"

server_is_up() {
	if which wget >/dev/null; then
		if wget -O - $url >/dev/null; then
			return 0
		fi
	elif which curl >/dev/null; then
		if curl $url >/dev/null; then
			return 0
		fi
	else
		ctx logger error "Both curl, wget not found in path"
		exit 1
	fi
	return 1
}

STARTED=false
for i in $(seq 1 15)
do
	if server_is_up; then
		ctx logger info "Server is up on port ${port}"
		STARTED=true
    	break
	else
		ctx logger info "Server not started. Waiting 1 second."
		sleep 1
	fi
done
if [ ${STARTED} = false ]; then
	ctx logger error "Failed starting web server in 15 seconds."
	exit 1
fi
