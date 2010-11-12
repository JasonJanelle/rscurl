#!/bin/bash
# by Jason Janelle
#rscurl -u username -a apiKey -c command [ -s serverID ] [ -n name ] [ -i imageID ] [ -f flavorID ] [ -q -h ]
#	v 0.1
#	rscurl is a command line tool for managing Rackspace Cloud Servers.  It uses curl, awk, sed, 
#	and tr to accomplish this in the hopes that it will work on most systems that use bash.  
#	
#	-u Your rackspace username.
#	-a Your rackspace api key, found on your rackspace cloud dashboard under Your Account, API Access.
#	   This cannot be your password.
#	-c command, possible commands are:
#		list-servers	- Lists all the servers you have on your account.
#		list-flavors	- Lists all the types of server that are available to you.
#		list-images		- Lists all the server images that are available to you.
#		create-server	- Creates a new server
#						  requires an imageID (-i) and flavorID (-f)
#						  optional name (-n)
#		delete-server	- Deletes a server, requires serverID (-s).
#						  DANGER: Server deleted without prompt, be sure.
#		rebuild			- Rebuilds a server with the new image, all data will be lost.
#						  requires an imageID (-i) and serverID (-s)
#		resize			- Resizes a server, requires flavorID (-f)
#		confirm-resize	- Confirms a recently resized server, after 24 hours it is done automatically.
#						  requires serverID (-s)
#		revert-resize	- Reverts a recently resized server to the previous size.
#						  requires serverID (-s)
#		reboot			- Reboots a server, requires serverID (-s)
#		force-reboot	- Forces a server to reboot, equivalent to pulling the power.
#		 				  Requires serverID (-s)
#		create-image	- Creates a new image based on an existing server.
#						  Requires serverID (-s), optional name (-n)
#		delete-image	- Deletes a server image that you own.
#						  Requires imageID (-i)
#	-s Server ID, required for some commands. To see the servers run list-servers.
#	-i Image ID, required for some commands. To see the images run list-images.
#	-f Flavor ID, required for some commands.  To see the flavors run list-flavors.
#	-n Name of server(required) or image(optional) when creating them.  
#	-q Quiet mode, all commands except list-* will exit quietly
#	-h show this menu
#
# FUNCTIONS
#
#prints out the usage information on error or request.
function usage () {
	printf "\n"
	printf "rscurl -u username -a apiKey -c command [ -s serverID ] [ -n name ] [ -i imageID ] [ -f flavorID ] [ -q -h ]\n"
	printf "\tv 0.1\n"
	printf "\trscurl is a command line tool for managing Rackspace Cloud Servers.  It uses curl, awk, sed, \n"
	printf "\tand tr to accomplish this in the hopes that it will work on most systems that use bash.\n"
	printf "\n"
	printf "\t-u Your rackspace username.\n"
	printf "\t-a Your rackspace api key, found on your rackspace cloud dashboard under Your Account, API Access.\n"
	printf "\t   This cannot be your password.\n"
	printf "\t-c command, possible commands are:\n"
	printf "\t\tlist-servers\t- Lists all the servers you have on your account.\n"
	printf "\t\tlist-flavors\t- Lists all the types of server that are available to you.\n"
	printf "\t\tlist-images\t\t- Lists all the server images that are available to you.\n"
	printf "\t\tcreate-server\t- Creates a new server\n"
	printf "\t\t\t\t\t\t  requires an imageID (-i) and flavorID (-f)\n"
	printf "\t\t\t\t\t\t  optional name (-n)\n"
	printf "\t\tdelete-server\t- Deletes a server, requires serverID (-s).\n"
	printf "\t\t\t\t\t\t  DANGER: Server deleted without prompt, be sure.\n"
	printf "\t\trebuild\t\t\t- Rebuilds a server with the new image, all data will be lost.\n"
	printf "\t\t\t\t\t\t  requires an imageID (-i) and serverID (-s)\n"
	printf "\t\tresize\t\t\t- Resizes a server, requires flavorID (-f)\n"
	printf "\t\tconfirm-resize\t- Confirms a recently resized server, after 24 hours it is done automatically.\n"
	printf "\t\t\t\t\t\t  requires serverID (-s)\n"
	printf "\t\trevert-resize\t- Reverts a recently resized server to the previous size.\n"
	printf "\t\t\t\t\t\t  requires serverID (-s)\n"
	printf "\t\treboot\t\t\t- Reboots a server, requires serverID (-s)\n"
	printf "\t\tforce-reboot\t- Forces a server to reboot, equivalent to pulling the power.\n"
	printf "\t\t\t\t\t\t  Requires serverID (-s)\n"
	printf "\t\tcreate-image\t- Creates a new image based on an existing server.\n"
	printf "\t\t\t\t\t\t  Requires serverID (-s), optional name (-n)\n"
	printf "\t\tdelete-image\t- Deletes a server image that you own.\n"
	printf "\t\t\t\t\t\t  Requires imageID (-i)\n"
	printf "\t-s Server ID, required for some commands. To see the servers run list-servers.\n"
	printf "\t-i Image ID, required for some commands. To see the images run list-images.\n"
	printf "\t-f Flavor ID, required for some commands.  To see the flavors run list-flavors.\n"
	printf "\t-n Name of server(required) or image(optional) when creating them.\n"
	printf "\t-q Quiet mode, all commands except list-* will exit quietly\n"
	printf "\t-h Show this menu.\n"
	printf "\n"
}
#Authenticates to the Rackspace Service and sets up the Authentication Token and Managment server
#REQUIRES: 1=AuthUser 2=API_Key
function get_auth () {
	AUTH=`curl -s -X GET -D - -H X-Auth-User:\ $1 -H X-Auth-Key:\ $2 https://auth.api.rackspacecloud.com/v1.0|tr -s [:cntrl:] "\n" \
		|awk '{ if ($1 == "HTTP/1.1") printf "%s,", $2 ; if ($1 == "X-Auth-Token:") printf "%s,", $2 ; if ($1 == "X-Server-Management-Url:") printf "%s,", $2 ;}' `
	EC=`echo $AUTH|awk -F, '{print $1}'`
	if [[ $EC == "204" ]]; then
		TOKEN=`echo $AUTH|awk -F, '{print $2}'`
		MGMTSVR=`echo $AUTH|awk -F, '{print $3}'`
	else
		if [[ $QUIET -eq 1 ]]; then
			exit $EC
		fi
		echo "Authentication Failed ($EC)"
		exit $EC
	fi
}
#Deletes and existing server or image
#REQUIRES: 1=AuthToken 2=RS_Management_Server 3=ServerID_or_ImageID_to_be_deleted 4="servers"|"images"
# "servers" will cause a server to be deleted
# "images" will cause an image to be deleted
function rsdelete () {
	#echo curl -s -X DELETE -D - -H X-Auth-Token:\ $1 $2/$4/$3
	RC=`curl -s -X DELETE -D - -H X-Auth-Token:\ $1 $2/$4/$3|tr -s [:cntrl:] "\n" |grep "HTTP/1.1"`
	#echo $RC
	http_code_eval `echo $RC|awk '{print $2}' `
}
#Creates a new server.
#REQUIRES: 1=AuthToken 2=RS_Management_Server 3=server.host.name 4=imageID_to_build_server 5=flavorID_of_the_new_server
function create_server () {
	#'{"server" : {"name" : "new-server-test","imageId" : 69,"flavorId" : 1,"metadata" : {"My Server Name" : "Testing"}}}'
	RSPOST="{\"server\":{\"name\":\"$3\",\"imageId\":$4,\"flavorId\":$5}}"
	RC=`curl -s -X POST -H X-Auth-Token:\ $1 -H Content-Type:\ application/json --data $RSPOST $2/servers|tr -s [:cntrl:] "\n"`
	#echo $RC
	case `echo $RC|awk -F: '{print $1}'|sed -e 's/{"//' -e 's/"//'` in
		server	)
			if [[ $QUIET -eq 1 ]]; then
				exit 0;
			fi
			printf "%-7s%-10s%-50s%-50s%-20s%-20s\n" ID Status Server\ Name Admin\ Password Public\ IP Private\ IP
			echo ------ --------- ------------------------------------------------- ------------------------------------------------- ------------------- ------------------- 
			echo $RC|sed -e 's/{"server":{//' -e 's/}}//' -e 's/"addresses":{//' \
		    |awk -F]} '{ printf "%s]\n", $1 }'|awk -F: 'BEGIN { RS = "," } ; { printf "%s,", $2 }' \
			|awk -F, '{printf "%-7s%-10s%-50s%-50s%-20s%-20s\n", $2, $5, $7, $6, $9, $10}'
			;;
		*		)
			EC=`echo $RC|sed 's/}}//'|awk -F\": '{print $NF}'`
			if [[ $QUIET -eq 1 ]]; then
				exit $EC
			fi
			output=`echo $RC|awk -F: '{print $1}'|sed -e 's/{"//' -e 's/"//'`
			output=$output:\ `echo $RC|awk -Fmessage\":\" '{print $2}'|awk -F\", '{print $1}'`
			echo $output
			exit $EC
			;;
	esac
}
#Creates a new server image based on an existing server.
#REQUIRES: 1=AuthToken 2=RS_Management_Server 3=Server_ID_to_be_imaged
#OPTIONAL: 4=Name_of_new_image
function create_image () {
	RSPOST="{\"image\":{\"serverId\":$3,\"name\":\"$4\"}}"
	RC=`curl -s -X POST -H X-Auth-Token:\ $1 -H Content-Type:\ application/json --data $RSPOST $2/images|tr -s [:cntrl:] "\n"`
	case `echo $RC|awk -F: '{print $1}'|sed -e 's/{"//' -e 's/"//'` in
		image	)
			if [[ $QUIET -eq 1 ]]; then
				exit 0;
			fi
			echo $RC
			printf "%-10s%-10s%-50s%-30s%-10s\n" Image\ ID Server\ ID Name Created Status
			echo --------- --------- ------------------------------------------------- ----------------------------- --------- 
			echo $RC|sed -e 's/{"image":{//' -e 's/}}//' |awk -F\": 'BEGIN { RS = "," } ; { printf "%s,", $2 }' \
			|awk -F, '{printf "%-10s%-10s%-50s%-30s%-10s\n", $1, $5, $4, $3, $2}'
			;;
		*		)
			EC=`echo $RC|sed 's/}}//'|awk -F\": '{print $NF}'`
			if [[ $QUIET -eq 1 ]]; then
				exit $EC
			fi
			output=`echo $RC|awk -F: '{print $1}'|sed -e 's/{"//' -e 's/"//'`
			output=$output:\ `echo $RC|awk -Fmessage\":\" '{print $2}'|awk -F\", '{print $1}'`
			echo $output
			exit $EC
			;;
	esac
}
#Retreives the list of server images from Rackspace
#REQUIRES: 1=AuthToken 2=RS_Management_Server
function get_images () {
	IMAGES=`curl -s -X GET -H X-Auth-Token:\ $1 $2/images|tr -s [:cntrl:] "\n" \
	    |sed -e 's/{"images":\[{//' -e 's/}\]}//' -e 's/},{/;/g' -e 's/"id"://g' -e 's/"name"://g'`
}
#Retreives the list of server flavors from Rackspace
#REQUIRES: 1=AuthToken 2=RS_Management_Server
function get_flavors () {
	FLAVORS=`curl -s -X GET -H X-Auth-Token:\ $1 $2/flavors|tr -s [:cntrl:] "\n" \
	    |sed -e 's/{"flavors":\[{//' -e 's/}\]}//' -e 's/},{/;/g' -e 's/"id"://g' -e 's/"name"://g'`
}
#Retreives the list of servers from Rackspace
#REQUIRES: 1=AuthToken 2=RS_Management_Server
function get_servers () {
	SERVERS=`curl -s -X GET -H X-Auth-Token:\ $1 $2/servers|tr -s [:cntrl:] "\n" \
	    |sed -e 's/{"servers":\[{//' -e 's/}\]}//' -e 's/},{/;/g' -e 's/"id"://g' -e 's/"name"://g'`
}
#Prints the header for the server list.
function print_server_header () {
	printf "%-7s%-40s%-20s%-10s%-50s%-20s%-20s\n" ID Server\ Image Server\ Flavor Status Server\ Name Public\ IP Private\ IP
	echo ------ --------------------------------------- ------------------- --------- ------------------------------------------------- ------------------- ------------------- 
}
#Prints the header for the flavor list.
function print_flavor_header () {
	printf "%-6s%-9s%-9s%s\n" ID RAM\(M\) Disk\(G\) Flavor\ Name
	echo ----- -------- -------- ---------- 
}
#Prints the header for the image list.
function print_image_header () {
	printf "%-10s%-40s%-10s%-30s%-30s\n" ID Status Date\ Created Date\ Updated Image\ Name
	echo --------- --------------------------------------- --------- ----------------------------- -----------------------------
}
#Prints a formatted list of the servers.
function print_servers () {
	print_server_header
	get_images $TOKEN $MGMTSVR
	get_flavors $TOKEN $MGMTSVR
	get_servers $TOKEN $MGMTSVR
	if [[ `echo $SERVERS|grep ,|wc -l` -eq 0 ]]
		then
		exit 0
	fi
	for i in `echo $SERVERS|awk -F, 'BEGIN { RS = ";" } ; {print $1}'`
	do 
		MYSERVER=`curl -s -X GET -H X-Auth-Token:\ $TOKEN $MGMTSVR/servers/$i|tr -s [:cntrl:] "\n" \
		    |sed -e 's/{"server":{//' -e 's/}}//' -e 's/"addresses":{//' \
		    |awk -F]} '{ printf "%s]\n", $1 }'|awk -F: 'BEGIN { RS = "," } ; { printf "%s,", $2 }'`
		imgid=`echo $MYSERVER|awk -F, '{print $3}'`
		MYIMAGE=`echo $IMAGES|awk -F, 'BEGIN { RS = ";" } ; { printf "X%s,%s\n" , $1, $2; }' \
		    |grep X$imgid|awk -F, '{print $2}'|sed 's/\ /-/g'`
		flvid=`echo $MYSERVER|awk -F, '{print $4}'`
		MYFLAVOR=`echo $FLAVORS|awk -F, 'BEGIN { RS = ";" } ; { printf "X%s,%s\n" , $1, $2; }' \
		    |grep X$flvid|awk -F, '{print $2}'|sed 's/\ /-/g'`
		echo $MYSERVER|awk -F, '{printf "%-7s", $2}'
		printf "%-40s%-20s" $MYIMAGE $MYFLAVOR
		echo $MYSERVER|awk -F, '{printf "%-10s%-50s%-20s%-20s\n", $5, $6, $8, $9}'
	done
}
#Prints a formatted list of the server flavor.
function print_flavors () {
	print_flavor_header
	get_flavors $TOKEN $MGMTSVR
	#echo $FLAVORS|awk -F, 'BEGIN { RS = ";" } ; {printf "%-10s%-20s\n", $1, $2}'
	for i in `echo $FLAVORS|awk -F, 'BEGIN { RS = ";" } ; {print $1}'`
	do
		curl -s -X GET -H X-Auth-Token:\ $TOKEN $MGMTSVR/flavors/$i|tr -s [:cntrl:] "\n" \
			|sed -e 's/{"flavor":{//' -e 's/}}//' |awk -F: 'BEGIN { RS = "," } ; { printf ",%s", $2 }' \
			|awk -F, '{printf "%-5s%8s%8s   %s\n", $2, $3, $4, $5}'
	done
}
#Prints a formatted list of the server images.
function print_images () {
	print_image_header 
	get_images $TOKEN $MGMTSVR
	#echo $IMAGES|awk -F, 'BEGIN { RS = ";" } ; {printf "%-10s %-40s\n", $1, $2}'
	for i in `echo $IMAGES|awk -F, 'BEGIN { RS = ";" } ; {print $1}'`
	do 
		MYIMAGE=`curl -s -X GET -H X-Auth-Token:\ $TOKEN $MGMTSVR/images/$i|tr -s [:cntrl:] "\n" |sed -e 's/{"image":{//' -e 's/}}//' `
		if [[ `echo $MYIMAGE |awk -F: '{print $1}'|grep progress|wc -l` -eq 1 ]]
			then
			echo -n $MYIMAGE |	awk -F\": 'BEGIN { RS = "," } ; { printf "%s,", $2 }' \
			|awk -F,	 '{printf "%-10s%-40s%-10s%-30s%-30s\n", $2, $6, $3, $4, $5}'
		else
			echo -n $MYIMAGE |	awk -F\": 'BEGIN { RS = "," } ; { printf "%s,", $2 }' \
			|awk -F, '{printf "%-10s%-40s%-10s%-30s%-30s\n", $1, $5, $2, $3, $4}'
		fi
	done
}
#Reboot server
# REQUIRES: 1=AuthToken 2=RS_Management_Server 3=Server_ID_To_Be_Rebooted 4="HARD"|"SOFT"
# Soft reboot sends the host OS a signal to reboot.
# Hard reboot is equivilent to pulling the plug and turning it back on.
function reboot () {
	RSPOST="{\"reboot\":{\"type\":\"$4\"}}"
	#echo $RSPOST
	http_code_eval `curl -s -X POST -D - -H X-Auth-Token:\ $1 -H Content-Type:\ application/json --data $RSPOST $2/servers/$3/action|tr -s [:cntrl:] "\n"|grep "HTTP/1.1"|awk '{print $2}' `
}
#Rebuild server with a new image.
# REQUIRES: 1=AuthToken 2=RS_Management_Server 3=Server_ID_To_Be_Rebuilt 4=Image_ID_to_put_server
function rebuild () {
	RSPOST="{\"rebuild\":{\"imageId\":$4}}"
	http_code_eval `curl -s -X POST -D - -H X-Auth-Token:\ $1 -H Content-Type:\ application/json --data $RSPOST $2/servers/$3/action|tr -s [:cntrl:] "\n"|grep "HTTP/1.1"|awk '{print $2}' `
}
#Resize server
# REQUIRES: 1=AuthToken 2=RS_Management_Server 3=Server_ID_To_Be_Resized 
function resize () {
	RSPOST="{\"resize\":{\"flavorId\":$4}}"
	http_code_eval `curl -s -X POST -D - -H X-Auth-Token:\ $1 -H Content-Type:\ application/json --data $RSPOST $2/servers/$3/action|tr -s [:cntrl:] "\n"|grep "HTTP/1.1"|awk '{print $2}' `
}
#Confirms that a server resize has worked
# REQUIRES: 1=AuthToken 2=RS_Management_Server 3=Server_ID_That_Was_Resized
function confirm_resize () {
	RSPOST="{\"confirmResize\":null}"
	http_code_eval `curl -s -X POST -D - -H X-Auth-Token:\ $1 -H Content-Type:\ application/json --data $RSPOST $2/servers/$3/action|tr -s [:cntrl:] "\n"|grep "HTTP/1.1"|awk '{print $2}' `
}
#Reverts a server that has been resized.
# REQUIRES: 1=AuthToken 2=RS_Management_Server 3=Server_ID_To_Be_Reverted
function revert_resize () {
	RSPOST="{\"revertResize\":null}"
	http_code_eval `curl -s -X POST -D - -H X-Auth-Token:\ $1 -H Content-Type:\ application/json --data $RSPOST $2/servers/$3/action|tr -s [:cntrl:] "\n"|grep "HTTP/1.1"|awk '{print $2}' `
}
#For commands that have no output, this function will evaluate the HTTP return code.
function http_code_eval () {
	if [ $QUIET -eq 1 ]
		then
		case $1 in
			202 ) exit 0 ;;
			204	) exit 0 ;;
			* ) exit $1 ;;
		esac
	else
		case $1 in
			202	) echo "Action request successful." ; exit 0;;
			204	) echo "Action request successful." ; exit 0;;
			401 ) echo "Request Unauthorized.  Is your username and api key correct?"; exit $1;;
			404	) echo "Server ID not found."; exit $1;;
			409	) echo "Server is currently being built, please wait and retry."; exit $1;;
			413	) echo "API Request limit reached, please wait and retry."; exit $1;;
			503	) echo "Rackspace Cloud service unavailable, please check and then retry."; exit $1;;
			*	) echo "An unknown error has occured. ($RC)"; exit 99;;
		esac
	fi
}
#Variables
QUIET=0
#Check for enough variables, print usage if not enough.
if [ $# -lt 6 ]
	then
	usage
	exit 1
fi
#Get options from the command line.
while getopts "u:a:c:s:n:i:f:hq" option
do
	case $option in
		u	) RSUSER=$OPTARG ;;
		a	) RSAPIKEY=$OPTARG ;;
		c	) MYCOMMAND=$OPTARG ;;
		s	) RSSERVID=$OPTARG ;;
		n	) MYNAME=$OPTARG ;;
		i	) RSIMAGEID=$OPTARG ;;
		f	) RSFLAVORID=$OPTARG ;;
		h	) usage;exit 0 ;;
		q	) QUIET=1 ;;
	esac
done
#All actions require authentication, get it done first.
#If the authentication works this will return $TOKEN and $MGMTSVR for use by everything else.
get_auth $RSUSER $RSAPIKEY
if test -z $TOKEN
	then 
	if [[ $QUIET -eq 0 ]]; then
		echo Auth Token does not exist.
	fi
	exit 98
fi
if test -z $MGMTSVR
	then 
	if [[ $QUIET -eq 0 ]]; then
		echo Management Server does not exist.
	fi
	exit 98
fi
#Evaluate which command we were asked to do.
case $MYCOMMAND in
	list-servers	) print_servers ;;
	list-flavors	) print_flavors ;;
	list-images		) print_images ;;
	delete-server	) 
		if test -z $RSSERVID
			then 
			if [[ $QUIET -eq 0 ]]; then
				echo Server ID not provided
			fi
			exit 98
		fi
		rsdelete $TOKEN $MGMTSVR $RSSERVID "servers" ;;
	create-server	) 
		if test -z $RSIMAGEID
			then 
			if [[ $QUIET -eq 0 ]]; then
				echo Image ID not provided
			fi
			exit 98
		fi
		if test -z $RSFLAVORID
			then 
			if [[ $QUIET -eq 0 ]]; then
				echo Flavor ID not provided
			fi
			exit 98
		fi
		if test -z $MYNAME
			then 
			if [[ $QUIET -eq 0 ]]; then
				echo Server Name not provided
			fi
			exit 98
		fi
		create_server $TOKEN $MGMTSVR $MYNAME $RSIMAGEID $RSFLAVORID ;;
	reboot			) 
		if test -z $RSSERVID
			then 
			if [[ $QUIET -eq 0 ]]; then
				echo Server ID not provided
			fi
			exit 98
		fi
		reboot $TOKEN $MGMTSVR $RSSERVID "SOFT" ;;
	force-reboot	) 
		if test -z $RSSERVID
			then 
			if [[ $QUIET -eq 0 ]]; then
				echo Server ID not provided
			fi
			exit 98
		fi
		reboot $TOKEN $MGMTSVR $RSSERVID "HARD" ;;
	rebuild			) 
		if test -z $RSSERVID
			then 
			if [[ $QUIET -eq 0 ]]; then
				echo Server ID not provided
			fi
			exit 98
		fi
		if test -z $RSIMAGEID
			then 
			if [[ $QUIET -eq 0 ]]; then
				echo Image ID not provided
			fi
			exit 98
		fi
		rebuild $TOKEN $MGMTSVR $RSSERVID $RRIMAGEID ;;
	resize			) 
		if test -z $RSSERVID
			then 
			if [[ $QUIET -eq 0 ]]; then
				echo Server ID not provided
			fi
			exit 98
		fi
		if test -z $RSFLAVORID
			then 
			if [[ $QUIET -eq 0 ]]; then
				echo Flavor ID not provided
			fi
			exit 98
		fi
		resize $TOKEN $MGMTSVR $RSSERVID $RRFLAVORID ;;
	confirm-resize	) 
		if test -z $RSSERVID
			then 
			if [[ $QUIET -eq 0 ]]; then
				echo Server ID not provided
			fi
			exit 98
		fi
		confirm_resize $TOKEN $MGMTSVR $RSSERVID ;;
	revert-resize	) 
		if test -z $RSSERVID
			then 
			if [[ $QUIET -eq 0 ]]; then
				echo Server ID not provided
			fi
			exit 98
		fi
		revert_resize $TOKEN $MGMTSVR $RSSERVID ;;
	create-image	) 
		if test -z $RSSERVID
			then 
			if [[ $QUIET -eq 0 ]]; then
				echo Server ID not provided
			fi
			exit 98
		fi
		create_image $TOKEN $MGMTSVR $RSSERVID $MYNAME ;;
	delete-image	) 
		if test -z $RSIMAGEID
			then 
			if [[ $QUIET -eq 0 ]]; then
				echo Image ID not provided
			fi
			exit 98
		fi
		rsdelete $TOKEN $MGMTSVR $RSIMAGEID "images" ;;
	*				) echo Unknown Command ; usage ; exit 2 ;;
esac
#done
exit 0