#!/usr/bin/bash
#ampQC
#Matt Bashton 2021
#Takes and input bed file of amplicons, a plate negative control bam file, and
#checks sample bam have enough depth to clear contamination level in negative.

# Set version
VERSION='0.1.4'

set -e -o pipefail

tput bold
echo "ampQC ${VERSION}"
echo "Matt Bashton 2021"
tput sgr0

# Transform long options to short ones
for ARG in "$@"; do
    shift
    case "${ARG}" in
	"--bed-file") set -- "$@" "-b" ;;
	"--bam-dir") set -- "$@" "-d" ;;
	"--neg-file") set -- "$@" "-n" ;;
	"--plate-list") set -- "$@" "-l" ;;
	"--help") set -- "$@" "-h" ;;
	"--version") set -- "$@" "-v" ;;
	"--all") set -- "$@" "-a" ;;
	"--exclude") set -- "$@" "-e" ;;
	"--amplicon-threshold") set -- "$@" "-t" ;;
	"--amplicon-uplift") set -- "$@" "-u" ;;
	"--output-list") set -- "$@" "-o" ;;
	"--prefix") set -- "$@" "-p" ;;
	"--bam-suffix") set "$@" "-s";;
	"--numb-threads") set -- "$@" "-c" ;;
	*) set -- "$@" "$ARG"
    esac
done

# Some defaults
ALL=false
AMP_THRESH='100'
AMP_UPLIFT='10'
PREFIX='ampQC'
SUFFIX='.sorted.bam'
OUTPUT='failed.txt'
REGEX="none set"
LIST=false
THREADS=4

function printUsage {

    cat << EOF
Takes and input bed file of amplicons, a plate negative control bam file, and
checks sample bam have enough depth to clear contamination level in negative.

Usage ampqc [ options ] --bam-dir <bam-dir> --bed-file <amplicons.bed> --neg-file <neg.bam> --plate-list <file with sample names on plate>

Required options:

-b --bed-file            bed file defining amplicons to use
-d --bam-dir             directory of bam files
-n --neg-file            file name of negative
-l --plate-list          text file of samples/file names (.bam extension optional) for the plate to investigate (not needed if -a is used)


Other options:

-h --help                print this message and exit
-v --version             print version and exit
-p --prefix              prefix to use for analysis [defaults to ampQC]
-s --bam-suffix          suffix appened to sample ID [defaults to .sorted.bam]
-a --all                 don't use the file above and process all bam files in a given directory
-e --exclude             prefixes to exclude in GNU grep Perl regex format, e.g. 'NEG|POS|BLANK' where | is or.
-t --amplicon-threshold  mean depth threshold for detecting elevated amplicons in negative, [default 100]
-u --amplicon-uplift     multiplier value required for letting potential contaminated amplicons pass [default 10]
-o --output-list         list of sample IDs which failed amplicon QC, [defaults to prefix.failed.txt]
-c --numb-threads        number of CPU threads for parallel tasks [default 4]

EOF
}

function fileExists {

    local FILE=${1}
    local DESC=${2}

    if [[ ! -f ${FILE} ]]; then
	echo "Error ${DESC} file: ${FILE} does not exist"
	return 1
    else
	return 0
    fi

}

function dirExists {

    local DIR=${1}
    local DESC=${2}

    if [[ ! -d ${DIR} ]]; then
	echo "Error ${DESC} directory: ${DIR} does not exist"
	return 1
    else
	return 0
    fi

}

function isNumeric {

    local NUMB=${1}
    local DESC=${2}

    if [[ ! -z "${NUM##*[!0-9]*}" ]]; then
	echo "Argument ${DESC}: ${NUMB} is not a number"
	return 1
    else
	return 0
    fi

}

OPTIND=1

# Flags to use later
B_FLAG=false
D_FLAG=false
N_FLAG=false
A_FLAG=false
L_FLAG=false
E_FLAG=false

while getopts b:d:n:l:p:s:e:t:u:o:c:havn OPTION
do
    case "${OPTION}" in

	b) # Bedfile for amplicons
	    BED=${OPTARG}
	    fileExists ${BED} bed
	    B_FLAG=true
	    ;;

	d) # Directory for input bam
	    DIR=${OPTARG%/}
	    dirExists ${DIR} 'input bam'
	    D_FLAG=true
	    ;;

	n) # File name of negative file
	    NEG=$(basename ${OPTARG})
	    fileExists ${DIR}/${NEG} 'negative bam'
	    N_FLAG=true
	    ;;

	a) # Work on ALL bam in input dir or not
	    ALL=true
	    A_FLAG=true
	    ;;

	e) # GNU grep -P expression to exlude files
	    REGEX=${OPTARG}
	    E_FLAG=true
	    ;;

	t) # Amplicon threshold
	    AMP_THRESH=${OPTARG}
	    isNumeric ${AMP_THRESH} "amplicon threshold"
	    ;;

	u) # Amplicon uplift
	    AMP_UPLIFT=${OPTARG}
	    isNumeric ${AMP_UPLIFT} "amplicon uplift value"
	    ;;

	o) # Output file for list of failed bam
	    OUTPUT=${OPTARG}
	    ;;

	l) # List of bam files for this plate to work on
	    LIST=${OPTARG}
	    fileExists ${LIST} 'list of plate bam'
	    L_FLAG=true
	    ;;

	p) # Prefix for output
	    PREFIX=${OPTARG}
	    ;;

	s) # Suffix for bam after sample ID
	    SUFFIX=${OPTARG}
	    ;;

	c) # Number of threads for parallel tasks
	    THREADS=${OPTARG}
	    ;;

	h) # Display help
	    printUsage
	    exit 1
	    ;;

	v) # Display version
	    echo "Version $VERSION"
	    ;;

	?) # Catch all
	    printUsage
	    exit 2
	    ;;
    esac
done
shift "$(($OPTIND -1))"

# Required arguments are: -b -d -n and -l or -a or -e
if ! ${B_FLAG} && ! ${D_FLAG} && ! ${N_FLAG} && ! ( ${L_FLAG} || ${A_FLAG} || ${E_FLAG} )
    then
    echo "Arguments -b -d -n and one of (-l -a -e) are required"
    printUsage
    exit 3
fi

# Assume all arguments are now correctly set
set -u

HOST=$(hostname)
TIME=$(date)

echo "** Parameters **"
echo " - Host: ${HOST}"
echo " - Current working directory: ${PWD}"
echo " - Time: ${TIME}"
echo " - User home dir: ${HOME}"
echo " - Amplicon bed file: ${BED}"
echo " - Input BAM dir: ${DIR}"
echo " - Negative BAM file: ${NEG}"
echo " - List of BAM files on plate: ${LIST}"
echo " - Pasrse all BAM in dir: ${ALL}"
echo " - Regex to use to filter BAM dir: ${REGEX}"
echo " - Threads for parallel jobs: ${THREADS}"
echo " - Threshold for high amplicon: ${AMP_THRESH}"
echo " - Multiplyer value for uplift to clear QC: ${AMP_UPLIFT}"
echo " - output prefix: ${PREFIX}"
echo " - sample bam suffix: ${SUFFIX}"
echo ""

# Get list of BAM files
# Is all mode set or are we using a list
if [[ ${ALL} = true ]]; then
    INPUT_BAM=( $(find ${DIR} -name '*.bam' -printf '%P\n' ) )
    echo "* ${#INPUT_BAM[@]} bam files found"
elif [[ ${L_FLAG} = true ]]; then
    INPUT_BAM=( $(find ${DIR} -name '*.bam' -printf '%P\n' | grep -f ${LIST} ) )
    echo "* ${#INPUT_BAM[@]} bam files found"
elif [[ ${E_FLAG} = true ]]; then
     INPUT_BAM=( $(find ${DIR} -name '*.bam' -printf '%P\n' | grep -vP "${REGEX}" ) )
     echo "* ${#INPUT_BAM[@]} bam files found"
fi

# Check neg for high amplicons
echo "* Examining negative for high amplicons"
samtools index ${DIR}/${NEG}
mosdepth -b ${BED} .mosdepth.${PREFIX}.neg ${DIR}/${NEG}
echo " - amplicons over threshold of ${AMP_THRESH}:"
declare -A AMP_DEPTH=()
while read -r AMP DEPTH
do
    AMP_DEPTH[$AMP]="$DEPTH"
done < <(zcat .mosdepth.${PREFIX}.neg.regions.bed.gz | awk -v x=${AMP_THRESH} '{ if($5 >= x) {print }}' | cut -f 4,5)
# Clean up files
rm .mosdepth*

# Count number of amplicons in hash
NO_AMPS=${#AMP_DEPTH[@]}
if [[ ${NO_AMPS} -eq 0 ]]; then
    echo -ne "\nNo amplicons detected in negative above mean depth threshold!\n"
    exit 0
fi

# Read these out
printf "%-20s %-20s\n" Amplicon Depth
for KEY in "${!AMP_DEPTH[@]}"
do
    printf "%-20s %-20.2f\n" ${KEY} ${AMP_DEPTH[${KEY}]}
done
echo ""

# Indexing all other bam
ALL_BAM=("${INPUT_BAM[@]}")
ALL_BAM+=(${NEG})
#Prefix dir and samtools index
PATH_ALL_BAM=( "${ALL_BAM[@]/#/samtools index ${DIR}/}" )

echo "* Indexing all bam on ${THREADS} threads..."
printf '%s\n' "${PATH_ALL_BAM[@]}" > .jobs.txt
parallel --jobs 4 --bar < .jobs.txt
rm .jobs.txt
echo ""

# Process all other bam
echo "* Getting depth on all other bam on ${THREADS} threads..."
# Create jobs
echo "" > .jobs.txt
for BAM in ${INPUT_BAM[@]}
do
    B_NAME=$(basename ${BAM} .bam)
    echo "mosdepth -b ${BED} .mosdepth.${PREFIX}.${B_NAME} ${DIR}/${BAM}" >> .jobs.txt
done
parallel --jobs 4 --bar < .jobs.txt
rm .jobs.txt
echo ""

# Iterate per file
echo "* Evaluating bam:"
echo ""
declare -a BAM_PASS=()
declare -a BAM_FAIL=()
for BAM in ${INPUT_BAM[@]}
do
    QC_PASS=true
    SAMPLE_ID=$(basename ${BAM} ${SUFFIX})
    SHORT_SUFFIX=$(basename ${BAM} .bam)
    MD_FILE=".mosdepth.${PREFIX}.${SHORT_SUFFIX}.regions.bed.gz"

    # Iterate per amplicon
    for AMPLICON in "${!AMP_DEPTH[@]}"
    do
	DEPTH=$(zcat ${MD_FILE} | awk -v x=${AMPLICON} '{if($4 == x)print $5}')
	#echo -ne "$B_NAME $AMPLICON $DEPTH "
	THRESHOLD=$(echo "scale=8; ${AMP_DEPTH[$AMPLICON]}*${AMP_UPLIFT}" | bc | xargs printf "%.2f\n")
	#echo -ne "${THRESHOLD} "
	if (( $(echo "$DEPTH < $THRESHOLD" | bc -l) )); then
	    QC_PASS=false
	    #echo -ne "${QC_PASS}"
	#else
	    #echo -ne "${QC_PASS}"
	fi
	#echo -ne "\n"
    done
    #echo "* ${QC_PASS}"
    if [[ ${QC_PASS} = false ]]; then
	BAM_FAIL+=(${SAMPLE_ID})
	echo -e ${SAMPLE_ID} '\xE2\x9D\x8C'
    elif [[ ${QC_PASS} = true ]]; then
	BAM_PASS+=(${SAMPLE_ID})
	echo -e ${SAMPLE_ID} '\xE2\x9C\x94'
    fi
done

# clean up files
rm .mosdepth*

# Stats
echo ""
echo "* Total passing: ${#BAM_PASS[@]}"
echo "* Total failing: ${#BAM_FAIL[@]}"
echo ""

# Write out results to filter to file
echo "Writing list of bam which failed QC to ${PREFIX}.${OUTPUT}"
printf "%s\n" "${BAM_FAIL[@]}" > ${PREFIX}.${OUTPUT}
exit 0
