output="$(ssh -qi ~/mykeypair root@${INSTANCE_IP} -p ${INSTANCE_PORT} '[[ -d /var/www/html/pub/repodata ]]' 2> /dev/null)"

test_passed=$?
check_message $test_passed "/var/www/html/pub/repodata exists"
