#!/bin/bash

# 전역 변수 설정
sleep_time=3			# 업데이트 주기
declare -i max=20		# 행 개수
blankw=" "				# 아무것도 없는 행을 채울 문자

usercnt=0				# 유저 개수
cmdscnt=0				# 커맨드 개수

cursor=1				# 현재 커서의 열 위치
curpos=0				# 현재 커서의 행 위치
cur1=0					# 첫 열의 커서 위치
cur2=0					# 두번째 열의 커서 위치

pads=( 20 20 5 9 )		# 파트 별로 몇 개의 글자를 출력할 것인지

lines=()				# 전체 줄
heads=()				# user 파트(글자)
tails=()				# cmd, pid, stime 파트(글자)
head_colors=()			# 각 user 파트 앞에 넣을 배경색상
tail_colors=()			# 각 cmd 파트 앞에 넣을 배경색상

get_line1() {
	# 첫 줄 반환
	# 일일히 -를 쳐가며 입력하면 오류가 날 수도 있고 읽기도 힘들기 때문에, spaces 배열을 선언하여 tags의 각 항목마다 -를 반복할 횟수를 지정해줍니다.
	# printf 함수는 다른 언어의 함수와 같이 "print Format"입니다. %.ns-는 -를 출력하고 n개 만큼 출력할 것을 의미합니다. {1..I}는 1~I까지 반복해서 출력할 것을 의미합니다.
	# seq는 터미널에서 실행할 수 있는 프로그램입니다. seq N M 은 N~M까지를 출력합니다. 
	# 즉, 반복 인자가 되는 string을 출력하지 않고 -를 출력(%.0s-), spaces[i]만큼 반복($seq 1 ${spaces[i]})
	# {1..~~~~} 대신 {1..${#spaces[i]}}로 대체해도 동일한 효과를 얻으실 것으로 생각합니다.
	line1="-"
	tags=( "-NAME" "-CMD" "-PID" "-STIME" )
	spaces=( 15 17 2 4 )
	for (( i=0; i<4; i++ )); do
		line1+="${tags[i]}"
		space=$(printf "%.0s-" {1..$(seq 1 ${spaces[i]})})
		line1+="${space}"
	done
	line1+="-"
}

get_padded_part() {
	# 파트에 공백을 채워넣어서 정렬을 유지함
	# 왼쪽 정렬이면 오른쪽에, 오른쪽정렬이면 왼쪽에 공백을 채워넣음
	# cut 역시 터미널에서 실행할 수 있는 프로그램. cut -c 1-N은 1~N번째 글자를 가져옴.
	# printf "${part}"로 전달받은 파트를 cut의 입력으로 전달함. cut -c 1-${pad}로 1~${pad}번째 글자를 가져와 저장.
	# 이후 필요한 부분에 공백을 저장.
	part=$1
	declare -i pad=$2
	left=$3
	loop=$((${pad}-${#part}))
	padded_str=""
	trunc_part=$(printf "${part}" | cut -c 1-${pad})
	if [[ $left == left ]]; then
		padded_str+="${trunc_part}""$(printf "%0.s " {1..$(seq 1 ${loop})})"
	else
		padded_str+="$(printf "%0.s " {1..$(seq 1 ${loop})})""${trunc_part}"
	fi
	echo "$padded_str"
}

get_padded_array() {
	# 배열에 최대값까지 빈 값을 채워넣음
	arr=("$@")
	for (( i=0; i<$(($max)); i++ )); do
		arr=(${arr[@]} $blankw)
	done
	echo ${arr[@]}
}

colorize() {
	# colorize 1 part and give it back
	# 41m: 배경 색 빨간색 42m: 배경 색 초록색 49m: 배경 색 없음
	color=$1
	colorcode=""
	case "$color" in
		"RED") colorcode="\e[41m";;
		"GREEN") colorcode="\e[42m";;
		"DEFAULT") colorcode="\e[49m";;
	esac
	echo $colorcode
}

red=$(colorize "RED")
green=$(colorize "GREEN")
default=$(colorize "DEFAULT")

build_head_parts() {
	# 새 user들을 받아옴
	# cat /etc/passwd 해보면 리스트가 뜨는데, 이 중 활용해야할 내용은 /bin/bash를 포함하는 항목(bash로 생성한 유저)임.
	# grep /bin/bash /etc/passwd는 /etc/passwd의 내용에서 /bin/bash를 붙잡아 출력으로 나타냄.
	# cut -f1 -d:에서 f1은 delimiter로 내용을 자를 것을 의미하고, -d:는 :를 delimiter로 할 것을 의미.
	# /etc/passwd에 root:~~~로 나타나있으면 user에 root만 저장됨
	users=( $(grep /bin/bash /etc/passwd | cut -f1 -d:) )
	usercnt=${#users[@]}
	users=($(get_padded_array ${users[@]}))
}

build_tail_parts() {
	# 인자로 전달된 user를 이용해서 그 user의 pid, cmd, stime을 가져옴
	# ps는 user, pid, comm, stime 등 여러 column을 포함함.
	# ps --user {user}로 어떤 user를 지정해서 볼 수 있음.
	# -o pid는 이름이 pid인 column만 볼 것을 의미. 이 때 첫 줄이 포함됨.
	# -o pid=는 첫 줄을 생략하고 pid만 보여줌.
	local user=$1
	pids=( $(ps --user ${user} -o pid=) )
	# pid 상위 20개만 필요하니 자름
	pids=( ${pids[@]:0:20} )
	pids=($(get_padded_array ${pids[@]}))
	cmds=()
	stimes=()
	for pid in ${pids[@]}; do
		if [[ $pid != $blankw ]]; then
			cmds+="$(ps --pid ${pid} -o comm=) "
			stimes+="$(ps --pid ${pid} -o stime=) "
		fi
	done
	cmds=($(get_padded_array ${cmds[@]}))
	stimes=($(get_padded_array ${stimes[@]}))

	cmdscnt=${#cmds[@]}
	if (( $cmdscnt > $max )); then
		cmdscnt=$max
	fi
}

build_head_and_tail() {
	# user, cmd, pid, stime을 모두 생성
	heads=()
	tails=()
	for (( i=0; i<$max; i++ )); do
		# initialize
		_head=""
		_tail=""
		parts=( "${users[i]}" "${cmds[i]}" "${pids[i]}" "${stimes[i]}" )

		# add to head
		_head="$(get_padded_part "${parts[0]}" "${pads[0]}" "right")"
		# add to tail
		for (( j=1; j<${#parts[@]}; j++ )); do
			if [[ $j == 1 ]]; then
				_tail+="$(get_padded_part "${parts[j]}" "${pads[j]}" "left")"
			else
				_tail+="$(get_padded_part "${parts[j]}" "${pads[j]}" "right")"
			fi
			if [[ $j != $((${#parts[@]}-1)) ]]; then
				_tail+="|"
			fi
		done

		# add head and tail to heads and tails
		heads=( "${heads[@]}" "$_head" )
		tails=( "${tails[@]}" "$_tail" )
	done
}

build_initial_parts() {
	# 초기 각 열 형성
	build_head_parts
	# for test, search by 1st user
	build_tail_parts ${users[0]}
	build_head_and_tail
}

make_new_line() {
	# 입력받은 색상과 파트를 이용해서 적절한 줄을 반환
	local head_color=$1
	local head=$2
	local tail_color=$3
	local tail=$4
	local def_color=$(colorize "DEFAULT")
	# 배경 색상 코드를 맨 앞에 넣어주기만 하면 그 뒤의 배경 색상도 변경됨
	local new_line="|""$head_color""$head""$def_color""|""$tail_color""$tail""$def_color""|\n"
	echo "$new_line"
}

make_frame() {
	get_line1
	# get first line
	lines+="${line1}\n"
	# get contents
	build_head_and_tail
	for (( i=0; i<$max; i++ )); do
		# add head and tail to next_line
		next_line=$(make_new_line "$default" "${heads[i]}" "$default" "${tails[i]}")
		# add next_line to lines
		lines+="${next_line}"
	done
	# get bottom border
	lines+="$(printf "%0.s-" {1..59})\n"
	# get last line
	lines+="\e[49mIf you want to exit , Please Type 'q' or 'Q'"
}

call_frame() {
	for (( i=0; i<${#lines[@]}; i++ )); do
		echo -e "${lines[i]}"
	done
}

initialize_color() {
	# 첫 줄의 색상을 각각 빨강, 초록으로 변환함
	local idx=0
	head_color[$idx]="$red"
	tail_color[$idx]="$green"
}

update_users() {
	build_head_parts
}

update_cmds() {
	local user=${users[$cur1]}
	build_tail_parts ${user}
	build_head_and_tail
	# 각 줄에서 amt만큼 커서를 올리고 지우고 새 줄을 넣고 다시 내림
	for (( i=0; i<$max; i++ )); do
		local amt=$((22-$i))
		new_line=$(make_new_line "${head_color[$i]}" "${heads[$i]}" "${tail_color[$i]}" "${tails[$i]}")
		printf "\033[${amt}A"
		printf "\033[K"
		# echo new line
		echo -e "$new_line"
		printf "\033[${amt}B"
	done
}

update_color_curr_curs() {
	local new_line=""
	local amt=$((22-$curpos))
	new_line=$(make_new_line "${head_color[$curpos]}" "${heads[$curpos]}" "${tail_color[$curpos]}" "${tails[$curpos]}")
	# delete current cursor line
	# 커서를 amt만큼 올리고 지운 뒤 새 줄을 넣고 amt만큼 다시 내림
	printf "\033[${amt}A"
	printf "\033[K"
	# echo new line
	echo -e "$new_line"
	printf "\033[${amt}B"
}

if_up_arrow() {
	# 위 방향이면 커서 열 위치에 따라 현재 커서의 색상을 지우고 그 윗 줄 색상을 업데이트
	# 커서가 첫 행까지 올라가지 않게 함
	if [[ $curpos > 0 ]]; then
		# 커서가 user에 있을 때
		if [[ $cursor == 0 ]]; then
			# 원래 위치는 기본 색상으로 바꾸고
			head_color[$curpos]="$default"
			# 색상 업데이트
			update_color_curr_curs
			# 다음 위치로 옮기고
			curpos=$(($curpos-1))
			cur1=$curpos
			# 현재 위치의 색상을 빨강으로 바꾸고
			head_color[$curpos]="$red"
			# 색상 업데이트
			update_color_curr_curs
			# 유저가 바뀌었으므로 커맨드 업데이트
			update_cmds
		elif [[ $cursor == 1 ]]; then
			tail_color[$curpos]="$default"
			update_color_curr_curs
			curpos=$(($curpos-1))
			cur2=$curpos
			tail_color[$curpos]="$green"
			update_color_curr_curs
		fi
	fi
}

if_down_arrow() {
	# 아래방향이면 커서 열 위치에 따라 현재 커서의 색상을 지우고 그 아래 줄 색상을 업데이트
	# 커서가 user에 있음 && 커서 위치가 제일 아래일때
	if (( $cursor == 0 && $curpos < $(($usercnt-1)) )); then
		# up와 비슷한 방식
		head_color[$curpos]="$default"
		update_color_curr_curs
		curpos=$(($curpos+1))
		cur1=$curpos
		head_color[$curpos]="$red"
		update_color_curr_curs
		update_cmds
	elif (( $cursor == 1 && $curpos < $(($cmdscnt-1)) )); then
		tail_color[$curpos]="$default"
		update_color_curr_curs
		curpos=$(($curpos+1))
		cur2=$curpos
		tail_color[$curpos]="$green"
		update_color_curr_curs
	fi
}

if_right_arrow() {
	# 우측이면 커서를 첫 줄로 놓고 첫 줄의 색상을 초록으로 업데이트
	# 커서가 user에 있으면
	if [[ $cursor != 1 ]]; then
		cur2=0
		curpos=0
		# 현재 위치(=0)의 색상을 초록으로 바꿈
		tail_color[$curpos]="$green"
		# 색상 업데이트
		update_color_curr_curs
		# 커서를 cmd로 옮김
		cursor=1
	fi
}

if_left_arrow() {
	# 좌측이면 현재 커서의 tail 색상을 지우고 업데이트
	if [[ $cursor != 0 ]]; then
		# cmd의 색상을 기본으로 바꿈
		tail_color[$curpos]="$default"
		# 색상 업데이트
		update_color_curr_curs
		# 저장된 user 커서 위치를 받아옴
		curpos=$cur1
		cursor=0
	fi
}

if_arrow_move() {
	# '\e[A' = 위 화살표 입력, ...
	input=$1
	case "$input" in
		$'\e[A') 
			if_up_arrow;;
		$'\e[B') 
			if_down_arrow;;
		$'\e[C') 
			if_right_arrow;;
		$'\e[D') 
			if_left_arrow;;
	esac
}

get_input() {
	# 프롬프트 입력을 숨김
	stty -echo
	# sleep_time 만큼 입력을 하나 받음
	while read -sN1 -t $sleep_time input; do 
		# 방향키를 입력받음
		# 0.001초마다 값을 받아와서 위 화살표를 예로 들면 \e, [, A를 따로 받아옴
		read -s -N1 -t 0.001 k1; read -sN1 -t 0.001 k2; read -sN1 -t 0.001 k3
		# 받아온 값을 input에 저장
		input+=${k1}${k2}${k3}
		case "$input" in
			q|Q) 
				# 종료 직전에 프롬프트 입력을 다시 보이게 함
				stty echo
				# 종료
				exit 1;;
			$'\e[A'|$'\e[B'|$'\e[C'|$'\e[D') if_arrow_move $input;;
		esac
	done
	# 유저 업데이트
	update_users
	# 커맨드 업데이트
	update_cmds
	# 반복
	get_input
}

# 로고 띄우기
get_large_char(){
	# 배열 내의 띄어쓰기를 띄어쓰기 그대로 쓰면,
	# bash의 배열은 띄어쓰기를 기준으로 나누기 때문에 의도치 않은 결과를 얻습니다.
	# 따라서 띄어쓰기 외의 글자로 대체하고(여기서는 ;) 이후 replace해서 결과를 얻습니다.
	c=$1
	case $c in
		"P") 
			_rslt=( "______;" "|;___;\\" "|;|_/;/" "|;;__/;"  "|;|;;;;" "\\_|;;;;" );;
		"r")
			_rslt=( ";;;;;;"  ";;;;;;"   ";____;"  "|;;__|"   "|;|;;;"  "|_|;;;"   );;
		"a")
			_rslt=( ";;;;;;;" ";;;;;;;"  ";;____;" ";/;_;;|"  "|;(_|;|" ";\\__,_|" );;
		"c")
			_rslt=( ";;;;;;" ";;;;;;"  ";;___;" ";/;__|"  "|;(__;" ";\\___|" );;
		"t")
			_rslt=( ";_;;;"   "|;|;;"    "|;|_;"   "|;__|"    "|;|_;"   ";\\__|"   );;
		"i")
			_rslt=( ";_;"	  "(_)"		 ";_;"	   "|;|"	  "|;|"	   "|_|"	   );;	
		"e")
			_rslt=( ";;;;;;"  ";;;;;;"	 ";;___;"  ";/;_;\\"  "|;;__/"  ";\\___|"  );;
		"n")
			_rslt=( ";;;;;;;" ";;;;;;;"  ";____;;" "|;;_;\\;" "|;|;|;|" "|_|;|_|"  );;
		"L")
			_rslt=( ";;;;;;;" "|;|;;;;"  "|;|;;;;" "|;|;;;;"  "|;|____" "\\_____/" );;
		"u")
			_rslt=( ";;;;;;;" ";;;;;;;"  ";_;;;_;" "|;|;|;|"  "|;|_|;|" ";\\__,_|" );;
		"x")
			_rslt=( ";;;;;;"  ";;;;;;"   "__;;__"  "\\;\\/;/" ";>;;<;" "/_/\\_\\" );;
	esac

	echo "${_rslt[@]}"
}


print_line() {
	line=$1 
	# line의 글자를 하나하나 분리 (ex: Practice = P r a c t i c e)
	# sed 's/찾을텍스트/바꿀텍스트/바꿀 줄', 마지막에 g 넣으면 찾은 모든 텍스트를 변환함
	# (.)로 각 글자를 찾음
	# \1는 괄호 안에서 얻은 문자를 capture하여 이용, \n은 한 줄을 띄움
	# 즉 각 문자 뒤에 \n을 추가해서 한 줄당 한 문자 출력
	# -e는 스크립트를 이용하겠다는 의미인데 빼도 괜찮을듯 합니다.
	line=$(echo "$line" | sed -e 's/\(.\)/\1\n/g')
	rslt_line=( "" "" "" "" "" "" )
	for c in ${line[@]}; do
		_rslt=( $(get_large_char "$c") )				# 결과 반환
		for (( i=0; i<6; i++ )); do
			rslt_line[$i]+=${_rslt[$i]//;/ }			# ;를 띄어쓰기로 변환한 값을 각 줄에 추가
		done
	done
	for (( i=0; i<6; i++ )); do
		echo "${rslt_line[i]}"
	done
}

# get_large_char P
print_line "Practice"
print_line "inLinux"

# user 등 제작
build_initial_parts
# 초기 상태의 창 만들기
make_frame
# 초기 상태의 창 띄우기
call_frame
# 각 부분 별 색상을 초기화
initialize_color
# 색상을 업데이트
update_color_curr_curs
# 프롬프트 입력을 받음
get_input
