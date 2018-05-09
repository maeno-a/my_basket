#!/bin/sh

export LANG=C
# git diffに行番号を追加する機能
diff_lines () {
  path=
  line=
  while read; do
    esc=$'\033'
    if [[ "$REPLY" =~ ---\ (a/)?.* ]]; then
      continue
    elif [[ "$REPLY" =~ \+\+\+\ (b/)?([^[:blank:]]+).* ]]; then
      path=${BASH_REMATCH[2]}
    elif [[ "$REPLY" =~ @@\ -[0-9]+(,[0-9]+)?\ \+([0-9]+)(,[0-9]+)?\ @@.* ]]; then
      line=${BASH_REMATCH[2]}
    elif [[ "$REPLY" =~ ^($esc\[[0-9;]+m)*([\ +-]) ]]; then
      echo "$path:::::$line:::::$REPLY"
      if [[ "${BASH_REMATCH[2]}" != - ]]; then
        ((line++))
      fi
    fi
  done
}

file_list () {
  # git diff で変更している内容を検索し以下の形で生成
  # ファイル名::::::行番号::::::変更後のソース
  # 切り出す為、ソース内で仕様しない文字列を間にはさんだ。
  # 生成内容はdiff_linesを参照
  # add 後の場合は　 --cachedをいれる
  DIFF=`git --no-pager diff --no-ext-diff -U1000000 | diff_lines | grep -E "^[^\"].*\:\:\:\:\:[0-9]+\:\:\:\:\:[\+]"`

  echo "$DIFF" | while read
  do
    arr=( `echo "$REPLY" | tr -d  ' ' |  sed -e "s/:::::/ /g"`)
    case "${arr[0]}" in
      app/models*)
        def=`sed -n "1,${arr[1]}p" ${arr[0]} | grep -ni "def " | tail -n 1`
        # 書き換えしたメソッドを判定
        # 判定方法：
        # ファイル内のメソッドと行番号の一覧を検索し、書き換えした行番号と比較、
        # 前にあるメソッドを書き換えたメソッドと判定
        method_name=`echo "$def" | sed '/^\S*def/d' | sed -e "s/^.*def \(.*\)(.*$/\1/" | cut -d"." -f2`
        if test "$method_name" != ""; then
          # メソッド名で影響しているファイルを検索する。
          # 同じメソッド名が別のファイルでもある場合は検索内容に入る場合がある。
          name=`grep -E "$method_name" -rl app` | sed 's/ /¥n/g'
          if [[ "$name" != "" ]]; then
            echo -e $name
          fi
          echo "${arr[0]}"
        else
          #has_one has_many belongs
          echo "${arr[0]}"
        fi
      ;;
      app/controllers*)
        # 取得したい内容
        #  class AbcdefgController < BaseController
        # 取得に省いている内容
        #  authorize_resource :setting, :class => "Abcdefg", :parent => false
        #  class Abcdefg < StandardError; end
        #  category_class = abcdefg.try(:class) || Abcdefg
        def=`sed -n "1,${arr[1]}p" ${arr[0]} | grep -ni "class [A-Z]" | grep -v " :class" | grep -v "end" | tail -n 1`
        # クラス名のみを取得
        class_name=`echo "$def" | sed -e "s/^.*class \(.*\) <.*$/\1/"`
        if test "$class_name" = "ApplicationController"; then
          echo "全コントローラに影響しています。"
        elif test "$class_name" != ""; then
          # 継承ファイルを調査
          name=`grep -E "(<.|::)$class_name" -rl app/controllers` | sed 's/ /¥n/g'
          if [[ "$name" != "" ]]; then
            echo -e $name
          fi
          echo "${arr[0]}"
        else
          echo "${arr[0]}"
        fi
      ;;
      app/views*)
        echo "${arr[0]}"
      ;;
      app/helper*)
        def=`sed -n "1,${arr[1]}p" ${arr[0]} | grep -ni "def " | tail -n 1`
        # 判定方法：
        # ファイル内のメソッドと行番号の一覧を検索し、書き換えした行番号と比較、
        # 前にあるメソッドを書き換えたメソッドと判定
        method_name=`echo "$def" | sed '/^\S*def/d' | sed -e "s/^.*def \(.*\)(.*$/\1/" | cut -d"." -f2`
        if test "$method_name" != ""; then
          # メソッド名で影響しているファイルを検索する。
          # 同じメソッド名が別のファイルでもある場合は検索内容に入る場合がある。
          name=`grep -E "$method_name" -rl  app/views` | sed 's/ /¥n/g'
          if [[ "$name" != "" ]]; then
            echo -e $name
          fi
        else
          echo "${arr[0]}"
        fi
      ;;
      lib*)
        def=`sed -n "1,${arr[1]}p" ${arr[0]} | grep -ni "class [A-Z]" | grep -v " :class" | grep -v "end" | tail -n 1`
        # クラス名またはモジュール名を検索
        if [[ "$def" != "" ]]; then
          class_name=`echo "$def" | sed -e "s/^.*class \(.*\) <.*$/\1/"`
        else
          def=`sed -n "1,${arr[1]}p" ${arr[0]} | grep -ni "module [A-Z]" | tail -n 1`
          class_name=`echo "$def" | sed -e "s/^.*module \(.*\).*$/\1/"`
        fi
        if test "$class_name" != ""; then
          # 継承ファイルを調査
          # 上記で取得したクラス名またはモジュール名の部分一致
          # 判定はextendかincludeか指定名か
          name=`grep -E "(extend.|include.|::)$class_name" -rl app` | sed 's/ /¥n/g'
          if [[ "$name" != "" ]]; then
            echo -e $name
          fi
          echo "${arr[0]}"
        else
          echo "${arr[0]}"
        fi
      ;;
      *) echo "${arr[0]}" ;;
    esac
  done
}
list=`file_list | sort | uniq | sed 's/\\n/'"$LF"'/g'`
# 該当ファイル名一覧を日本語化するための処理を実行
echo "${list}"




