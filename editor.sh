#!/bin/bash

# 程序功能：编写一个命令行编辑器程序，实现 vim 的部分功能

# 编辑器样式
#                    ┌─────────────┬────────────────────┬─────────────┐                       
#                    │    Info     │                    │   Prompt    │                       
#   ┌────────┐       ├────┬────────┴────────────────────┴─────────────┤                       
#   │top_most│──────▶│aaaa│                                           │──────┐                
#   └────────┘       ├────┴──┬────────────────────────────────────────┤      │                
#                    │bbbbbbb│                                        │──────┤                
#                    ├───────┴────────────────────────────────────────┤      │      ┌────────┐
#                    │                                                │──────┼─────▶│$LINES=5│
#                    ├─┬──────────────────────────────────────────────┤      │      └────────┘
#                    │c│                                              │──────┤                
#                    ├─┴───────────┬──────────────────────────────────┤      │                
#                    │ddddddddddddd│                                  │──────┘                
#                    ├─────────────┴────┬─────────────────────────────┤                       
#                    │ Path (When Open) │                             │                       
#                    └──────────────────┴─────────────────────────────┘           

declare -a buffer=() # 当前文件内容缓冲区
declare -i line=0 # 当前选中的行，初始为0，表示没有被选中
declare -i top_most=1 # 当前展示在屏幕的最上面的行号
declare file= # 当前打开的文件
declare prompt="Welcome to oneko editor (press 'q' to quit)" # 状态栏标语
declare is_modified=false # 跟踪某个文件是否被修改，初始为 false

# 模式设置

trap Display WINCH ALRM # 定时重绘、窗口大小改变时重绘 

# 读入文件路径并做初始化

function LoadFile(){
	printf '\e[?25h' # 显示光标
		
	if read -rei "$1$file" -p "Path: " file; then
		if [ ! -f "$file" ]; then 
			touch "$file" # 文件不存在则创建文件
		fi
		buffer=() # 清空 buffer，在此之前我们已经 DumpBuffer
		is_modified=true
		LoadBuffer # 加载到 buffer 中
	fi
}

# 将文件加载进 buffer 当中

function LoadBuffer(){
	# 将文件赋值给 buffer 数组，从下标1开始（这里是为了和 line 对应，因为 line 约定是从1开始的）
	mapfile -t -O 1 buffer <"$file" 

	num="$(grep -o '' <<< ${buffer[*]} | wc -l)" # 空行的个数

	if [[ $num==${#buffer[@]} ]] ; then # 判断文件空行数量和总行数是否相等来判断是否非空
		line=1 # 将光标设置在第一行
		is_modified=false # 刚将文件加载进来，没有被修改
		prompt="Read ${#buffer[@]} line(s) from '$file'" # 显示文件行数
	else
		prompt="'$file' is empty"
	fi
}

# 将文件从 buffer 中写出

function DumpBuffer(){
	true >"$file" # 将文件内容清空

	for item in "${buffer[@]}"; do
		echo "$item" >>"$file"
	done

	is_modified=false
	prompt="${#buffer[@]} line(s) dumped to '$file'" 
}

# 对一行中的文本进行编辑

function EditLine(){
	# 没有有效行可以编辑，直接返回
	if (( line == 0 )) ; then 
		return 
	fi

	IFS_OLD=$IFS # 保存旧的分隔符符
	IFS=$'\n' # 设置分隔符为 '\n'
	
	local -i new_cursor_pos=$line+2-$top_most # 新的光标坐标

	# local -i remains=$COLUMNS-5 # 该行剩余可显示字符数
	# local -i mod=$((${#buffer[line]}%$remains)) # 余数
	# local -i loops=$((${#buffer[line]}/$remains))+1 # 循环次数
	# (( mod ==0 )) && (( loops-- )) # 整行，如 $COLUMNS=90, ${#buffer[line]}=270 

	# printf '\e[%sH' "$((new_cursor_pos+loops-1))" 
	# printf '\e[K'
	printf '\e[?25h\e[%sH' "$new_cursor_pos" # 重新绘制光标的位置

	read -rei "${buffer[line]}" -p "$(printf '%4s ' "$line")" being_edited # 展示当前正在被编辑的行

	# 当前行被修改，更新并回显
	if [[ "$being_edited" != "${buffer[line]}" ]] ; then
		buffer[line]=$being_edited
		is_modified=true
	fi

	IFS=$IFS_OLD # 恢复分隔符
}

# 在当前编辑位置前插入新的一行，移动到该行并进入编辑模式

function NewLineForwards(){
        last_idx=${#buffer[@]} # buffer 最后一个元素的下标
        buffer=("" "${buffer[@]:1:line-1}" "" "${buffer[@]:line}") # 插入一个空行，新建 buffer 数组
        unset 'buffer[0]'
        is_modified=true # 设置修改标记为 true
        Display
        EditLine
}

# 在当前编辑位置后插入新的一行，移动到该行并进入编辑模式

function NewLineBackwards(){
	last_idx=${#buffer[@]} # buffer 最后一个元素的下标
	buffer=("" "${buffer[@]:1:line}" "" "${buffer[@]:line+1}") # 插入一个空行，新建 buffer 数组
	unset 'buffer[0]'
	is_modified=true # 设置修改标记为 true
	Down
	Display
	EditLine
}

# 删除当前位置的一行

function DeleteLine(){
	last_idx=${#buffer[@]} # buffer 最后一个元素的下标

	# 删除当前行，新建 buffer 数组	
	buffer=("" "${buffer[@]:1:line-1}" "${buffer[@]:line+1:$last_idx}") 
	
	unset 'buffer[0]'

	# 被删除的是最后一行，光标上移一行
	if (( line > ${#buffer[@]} )) ; then
		Up
	fi

	is_modified=true
}            

# 光标上移，默认1行

function Up(){
	
	# 未传入参数，默认1行
	ofs="$1"
	if [ ! -n "$ofs" ] ; then
		ofs=1
	fi

	for ((i = 0; i < $ofs; i++)); do
		# 可以向上移动，则向上移动一行
		if ((line > 1)) ; then
		       	((line--))
		fi
		# 移动到当前显示在屏幕上的最高行的上一行，更新显示在屏幕上的最高行
		if (( line < top_most )) ; then
			((top_most--))
		fi
		# 最高行已经是第一行，不再更新
		if (( top_most <= 0 )) ; then
			top_most=1
		fi
	done
}


# 光标下移，默认1行

function Down(){

	ofs="$1"
	if [ ! -n "$ofs" ] ; then
		ofs=1
	fi

	for ((i=0; i<$ofs; i++)); do
		# 可以向下移动，则向下移动一行
		if ((line<${#buffer[@]})) ; then
			((line++))
		fi
		# 超出当前屏幕最大显示行数，下移一行展示
		if ((line > top_most -1 + $LINES - 2)) ; then
			((top_most++))
		fi
	done
}

# 退出，并对 bufffer 做相应处理

function Quit(){
	# buffer 被修改
	if [ "$is_modified" == "true" ] ; then
		while :; do
			# 退出时提示是否保存，'y' 表示保存修改，'n' 表示不保存，'c' 表示继续编辑，暂不退出
			read -rsN 1 -p "You have modified something, save before close? [y/n/c]" choice
			printf '\n'
			case "$choice" in
				Y|y) DumpBuffer; echo "$prompt"; printf '\e[?25h'; exit 0;; # 保存后退出
				N|n) printf '\e[?25h'; exit 0;; # 不保存，直接退出
				C|c) prompt="Quit cancelled, continue editing"; break;; # 继续编辑
				*) continue;; # 输入了非 'Y/y', 'N/n', 'C/c' 的字符，要求继续输入
			esac
		done
	else
		printf '\e[?25h'
		exit 0
	fi
}	

# 绘制函数，用于及时回显文本:

function Display(){
	# 移动光标到 (0,0) 并设置光标不可见，标题栏设置为亮黑色，输出提示信息
	(printf '\e[H\e[?25l\e[100m%*s\r %s' "$COLUMNS" "$prompt"
        # 输出 logo
	printf  "📝 "
	# 格式化输出待编辑文件名，行号和该行的列数
	printf '\e[3;97;100m %s \e[0;100m Line:%s Col:%s\e[m' "$file" "$line" "${#buffer[line]}"
	printf '\n')	
	# 最大绘制行号
	local -i max_line=$top_most+$LINES-2
	# 绘制每一行
	for ((i = top_most; i < max_line; i++)); do
		# 如果当前行未被选中，淡化行号
		if ((i != line)) ; then
			printf '\e[90m'
		fi
		# 大于当前有内容的最大行号，则输出 '~' 作为行号
		if ((i > ${#buffer[@]})) ; then
			printf '\e[K\e[35m  ~\e[m\n'
		else # 否则正常输出行号以及内容
			# # 需要多行显示
			# if (( ${#buffer[i]} > $COLUMNS - 5)) ; then
			# 	local -i remains=$COLUMNS-5 # 该行剩余可显示字符数
			# 	local -i mod=$((${#buffer[i]}%$remains)) # 余数
			# 	local -i loops=$((${#buffer[i]}/$remains))+1 # 循环次数
			# 	(( mod ==0 )) && (( loops-- )) # 整行，如 $COLUMNS=90, ${#buffer[i]}=270 
			# 	((max_line=$max_line-loops+1)) # 更新最大绘制行数，减去因为多行显示额外占用的行
				
			# 	local str=${buffer[i]} # 该行文本赋值给字符串变量
			# 	printf '\e[K%4s\e[m %s\n' "$i" "${str[@]:0:remains}" # 第一行单独输出
			# 	for ((j=1; j<loops; j++)) ; do
			# 		(printf '\e[K\e[33m   >\e[m '
			# 		printf ${str[@]:$remains*j:remains}
			# 		printf '\n')
			# 	done
			# else # 不用多行展示
			# 	printf '\e[K%4s\e[m %s\n' "$i" "${buffer[i]}"
			# fi
			printf '\e[K%4s\e[m %s\n' "$i" "${buffer[i]}"
		fi
	done
}

# 键盘键绑定

function KeyBinding(){
	case "$1" in
		$'\E[A'*) Up;; # 上移一行		       
		$'\E[B'*) Down;; # 下移一行
		q) Quit;; # 按 'q' 退出
		f) DumpBuffer; LoadFile;; # 初始化文件
		e) EditLine;; # 编辑一行
		d) DeleteLine;; # 删除一行
		w) DumpBuffer;; # 保存已写内容
		n) NewLineBackwards;; # 在当前编辑行之后添加一行
		b) NewLineForwards;; # 在当前编辑行之前添加一行
	esac
}

# 主函数

function main(){
	
	# 给出的文件多于一个
	if [ $# -gt 1 ] ; then 
	       echo "Too many files!"
	       exit 1
	# 没有给出文件名
	elif [ $# -eq 0 ] ; then
		echo "No file!"
		exit 1
	# 文件数目是一个，正确
	else
		Display
		LoadFile "$1" #加载文件内容
		local -a temp_buffer=() # 临时数组用于储存输入
		local -i idx=1 # 数组下标

		# 循环处理键盘输入
		while Display; do
			# 设置超时阈值（0.2s）刷新屏幕
			if read -rsN 1 -t 0.2 temp_buffer[0]; then
				while read -rsN 1 -t 0.002 temp_buffer[$idx]; do 
					((idx++))
				done

				KeyBinding "$(printf '%s' "${temp_buffer[@]}")"  # 处理键盘输入

				temp_buffer=() # 清空数组
				idx=1 # 下标重置
			fi
		done
	fi	
}

main "$@"
