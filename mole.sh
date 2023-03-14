 #!/bash/sh
#TODO: refactor
usage (){
    echo "Usage: mole [OPTIONS] [FILTERS] [DIRECTORY] [FILE]"
    echo "Wrapper for effective usage of text editor"
    echo "with option to automaticaly open the last or the most frequently modfied file"
    echo "Try mole -h for more information"
    if [ "$1" = "extended" ]; then
        echo "If DIRECTORY is NOT specified, current directory is used."
        echo "If FILE is NOT specified, the last edited file within DIRECTORY"
        echo "will be opened, if not specified otherweise (see -m, FILTERS)"
        echo "OPTIONS"
        echo "  -g GROUP     Opened file will be assigned to group GROUP"
        echo "  -m           Open file with the highest number of edits"
        echo "  list         List files within DIRECTORY which has been edited with mole"
        echo "FILTERS"
        echo "  -g GROUP1[,GROUP2[,...]]"
        echo "  -a DATE"
        echo "  -b DATE"
    fi
}


checkDependencies(){
    # realpath
    realpath . 2>/dev/null || {
        echo "Error: Dependency realpath is not installed" 1>&2
        exit 1
    }
}

# Check whether MOLE_RC is set, return 1 if NOT
# If file specified by MOLE_RC does not exist create it
checkMOLE_RC(){
    # check whether MOLE_RC is set
    if [ -z "$MOLE_RC" ]; then
        return 1
    fi

    _MOLE_RC=$(eval realpath -m $MOLE_RC)
    directory=""

    # check whether MOLE_RC exists, otherwise create
    if ! [ -f "$_MOLE_RC" ]; then
        ## eval for case one of .. or . or ~ was used
        #dir=$(eval "echo $MOLE_RC")

        ## Extract PATH to the file
        directory=$(echo $_MOLE_RC | sed -r 's;/[^/]+$;/;g')
        ## create file if no PATH preceed filename
        #if [ "$dir" = "$MOLE_RC" ]; then
            #touch $MOLE_RC 2>/devl/null || {
                #return 1
            #}
            #return 0
        #fi

        if ! [ -d "$directory" ]; then
            mkdir -p "$directory" 2>/dev/null || {
                return 1
            }
        fi

        touch $_MOLE_RC 2>/dev/null || {
            return 1
        }
    fi
    return 0
}

setEDITOR(){
    # Use EDITOR if set
    _EDITOR=$EDITOR
    if [ -z "$EDITOR" ]; then
        # otherwise VISUAL if set
        if [ -n "$VISUAL" ]; then
            _EDITOR=$VISUAL
        else
            # otherwise vi
            _EDITOR="vi"
        fi
    fi
}

parseMode(){
    # determine mode of script execution
    keyword=$1
    case $keyword in
        list)
            _MODE="list"
            shift 1
            ;;
        secret-log)
            _MODE="slog"
            shift 1
            ;;
        *)
            _MODE="edit"
            ;;
    esac
    _ARGV="$*"
}

parseOptions(){
    # Parse options
    OPTIND=1
    while getopts hmg:a:b: option
    do
        case ${option} in
        h)
            usage "extended"
            exit 0
            ;;
        m)
            _MOST_FREQUENT=1
            ;;

        g)
            _GROUPS=${OPTARG}
            ;;
        a)
            _START_DATE=$(date -d ${OPTARG} '+%F' 2>/dev/null) || {
                echo "Invalid date format. Expected YYYY-MM-DD" >&2
                exit 1
            }
            ;;
        b)
            _END_DATE=$(date -d ${OPTARG} '+%F' 2>/dev/null) || {
                echo "Inalid date fromat. Expected YYYY-MM-DD" >&2
                exit 1
            }
            ;;
        *)
            echo "Invalid combination of options" >&2
            usage
            exit 1
            ;;
        esac
    done

    OPTIND=$(OPTIND-1)
    shift $OPTIND
    _ARGV="$*"
}

#### FILTERS AND SPECIFIERS ####
_START_DATE=""              #
_END_DATE=""                #
_MOST_FREQUENT=0          #
_GROUPS=""                  #
_MODE=""

#### GLOBAL VARIABLES ####
_MOLE_RC=""           #
_EDITOR=""            #
_ARGV="$*"            #

# filters
laterThan(){
    date=$1
    if [ "$date" ]; then
        awk -F';' -v DATE="$date" '{split($4,arr," ")}
                                   {if (substr(arr[1],0,10)>=DATE)
                                    {print $0}}'
    else
        awk -F';' '{print $0}'
    fi
}

ealierThan(){
    date=$1
    if [ "$date" ]; then
        awk -F';' -v DATE="$date" '{n=split($4,arr," ")}
                                   {if (substr(arr[n],0,10)<=DATE)
                                    {print $0}}'
    else
        awk -F';' '{print $0}'
    fi
}

isInGroups() {
    groups=$1
    if [ "$groups" ]; then
        awk -F';' -v G="$groups" 'BEGIN {n_groups=split(G,req_groups,",")}
                                 {n_matches=0}
                                 {split($NF,curr_groups, " ")}
                                 {for (a in req_groups)
                                    {for (b in curr_groups)
                                        if (req_groups[a]==curr_groups[b]) {n_matches+=1}
                                    }
                                 }
                                 {if (n_matches==n_groups) {print $0}}
                                '
    else
        awk -F';' '{print $0}'
    fi
}


# update record based on filepath
updateRecord(){
    path="$1"
    filename_length=$(echo $path | awk -F'/' '{print length($NF)}')
    n_opens=1;
    date_full=$(date '+%F_%T' | tr ':' '-')
    new_group="$2"
    groups=""

    record=$(cat $_MOLE_RC | awk -F';' -v PATH=$path 'PATH==$1 {print $0}')
    updated_record=""
    if [ -z "$record" ]; then
        echo "$path;$filename_length;1;$date_full;$new_group" >> $_MOLE_RC
    else
       # update fileds
       n_opens=$(echo $record | cut -d';' -f3,3)
       n_opens=$(n_opens++)
       date_full=$(echo $record | cut -d';' -f4,4)" $date_full"
       groups=$(echo $record | cut -d';' -f5,5)

       # update groups
       if [ -n "$new_group" ]; then
            groups="$groups $new_group"
            groups=$(echo $groups | tr ' ' '\n' | sort -u | tr '\n' ' ')
       fi

        updated_record="$path;$filename_length;$n_opens;$date_full;$groups"

        # update mole_rc\
        awk -F';' -i inplace -v PATH="$path" -v NEW="$updated_record" '{}PATH!=$1 {print $0} ENDFILE {print NEW}' $_MOLE_RC
    fi
}

editFile(){
    path=""
    if [ $1 ]; then
        path=$(eval realpath -m $1) # eval for case path parameter was in form "path"
    else
        path=$(pwd)
    fi


    if [ -d $path ]; then
        # find and update file or raise error
        # edit foudn file
        if [ $_MOST_FREQUENT -eq 1 ]; then
            path=$(cat $_MOLE_RC | grep "$path/" | sort -t';' -k3,3n | tail -n 1 | cut -d';' -f1,1)
        else
            path=$(cat $_MOLE_RC | grep "$path/" | tail -n 1 | cut -d';' -f1,1)
        fi
    fi

    if [ -z "$path" ]; then
        echo "Canot choose file to open" >&2
        exit 1;
    fi


    $_EDITOR $path 2> /dev/null || {
        echo "Unable to open given $path with $_EDITOR"
        exit 1;
    }

    if [ -f $path ]; then
        updateRecord "$path" "$_GROUPS"
    else
        # remove from records if the file was deleted
        awk -F';' -i inplace -v PATH=$path '$1 != PATH {print $0}' $_MOLE_RC
    fi
}


listFiles(){
    path=""
    if [ $1 ]; then
        path=$(realpath -m $1)
    fi

    if [ -d $path ]; then
        cat $_MOLE_RC | grep "$path/" | isInGroups $_GROUPS
    else
        echo "Invalid non-positional parameter" >&2;
        exit 1;
    fi
}


createSecretLog(){
    dir_regex=""
    current_directory=""
    if [ "$*" ]; then
        for dir in "$@"
        do
            current_directory=$(realpath -m $dir)
            if [ -d $current_directory ]; then
                dir_regex="${dir_regex};\|${current_directory}"
            fi
        done
        # cut-off first 3 character ;\|
        dir_regex=$(echo $dir_regex | sed 's#;\\|##')
    fi
}

main(){
    checkMOLE_RC || {
        echo "Invalid or UNSET filepath specified by MOLE_RC";
        exit 1;
    }
    setEDITOR

    parseMode $_ARGV
    # TODO: comment - allows changes made to _ARGV processed form function scope
    parseOptions $_ARGV


    case $_MODE in
        edit)
            editFile $_ARGV
        ;;
        list)
            listFiles $_ARGV
        ;;
        slog)
            createSecretLog $_ARGV
        ;;
    esac



    exit 0
}


### MAIN
main _ARGV
