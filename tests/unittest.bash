

testsuite() {
    exec 3>&1  # so tests can put ouput to &3
    local suitename
    suitename=$1
    shift

    eval ${suitename}_test_list=""
    while [ $# -gt 0 ]
    do
       case "x$1" in
       x-s) eval ${suitename}_test_setup=$2; shift; shift;;
       x-t) eval ${suitename}_test_teardown=$2; shift; shift;;
       x*)  eval ${suitename}_test_list=\"\$${suitename}_test_list $1\"; shift;;
       esac
    done

    local def
    def=" 
        ${suitename}() {
            local siglist=\"RETURN 0 1 2 3 4 5 6 7 8 10 11\"
            local verbose=\$1
            local n_tests
            local n_fails

            echo 'in $suitename verbose: \$verbose'

            if [ x\$verbose = "x--only" ]
            then
                ${suitename}_test_list=\"\$2\"
                verbose=\$3
            fi

            trap wrapup \$siglist

            : > ${TMPDIR:-/tmp}/test_out_$$

            n_tests=0
            n_fails=0
	    for _t in \$${suitename}_test_list
	    do
               n_tests=\$(( n_tests + 1 ))
	       if [ x\$verbose = "x-v" -o x\$verbose = "x-vv" ]
               then
	           printf '%s \t...' \$_t
               fi
	       \$${suitename}_test_setup > ${TMPDIR:-/tmp}/setup_out\$n_tests 2>&1
	       if \$_t > ${TMPDIR:-/tmp}/test_case_out_\$\$ 2>&1
               then
                   if [ x\$verbose = "x-v" -o x\$verbose = "x-vv" ]
                   then
                       echo ok
                   else
                       printf .
                   fi
                   if [  x\$verbose = "x-vv" ]
                   then
		       echo ============================== >> ${TMPDIR:-/tmp}/test_out_$$
		       echo PASS: \$_t >>  ${TMPDIR:-/tmp}/test_out_$$
		       echo ---------------- >> ${TMPDIR:-/tmp}/test_out_$$
		       cat  ${TMPDIR:-/tmp}/test_case_out_\$\$ >> ${TMPDIR:-/tmp}/test_out_$$
		       echo ---------------- >> ${TMPDIR:-/tmp}/test_out_$$
                   fi
               else
                   n_fails=\$(( n_fails + 1 ))
                   if [ x\$verbose = "x-v" -o x\$verbose = "x-vv" ]
                   then
                       echo FAIL
                   else
                       printf F
                   fi
                   echo ============================== >> ${TMPDIR:-/tmp}/test_out_$$
                   echo FAIL: \$_t >>  ${TMPDIR:-/tmp}/test_out_$$
                   echo ---------------- >> ${TMPDIR:-/tmp}/test_out_$$
                   cat  ${TMPDIR:-/tmp}/test_case_out_\$\$ >> ${TMPDIR:-/tmp}/test_out_$$
                   echo ---------------- >> ${TMPDIR:-/tmp}/test_out_$$
               fi
	       \$${suitename}_test_teardown > /dev/null 2>&1
            done
            echo
         }
     "
     #echo "def is $def" 
     eval "$def"
}

wrapup() {
    echo
    echo ==================================
    cat /tmp/test_out_$$
    echo ==================================
    echo Ran $n_tests tests with $n_fails failures
    if [ $n_fails = 0 ]
    then
        echo "ok"
    else
        echo "FAILED"
        false
    fi
    rm -f ${TMPDIR:-/tmp}/test_out_$$ ${TMPDIR:-/tmp}/test_case_out$$
    trap "" $siglist
    echo 'return trap'
}
