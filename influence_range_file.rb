# 影響範囲自動化スクリプト
# git diff のログデータを使用して変更してメソッドなどを割り出し、影響範囲を一覧にして表示する。
# 起動方法
# bundle exec rails runner script/development/influence_range_file.rb

# file_list
# * git diff情報を生成し、変更部分とファイルと行数を求める
# relation_file
# * ファイルの種類ごとに影響範囲の判別を実施
# range_file_value
# * ファイル名で影響する画面の名称を割り出し表示する。

class InfluenceRangeFile
  PICKUP_FILE = [
    "controllers",
    "models",
    "views"
  ].freeze

  @diff_gets = []
  @relation_files = []

  class << self
    def file_list
      diff_get
      relation_file
      range_file_value
    end

    def diff_get
      diff = `git --no-pager diff --no-ext-diff -U1000000`
      diff_list = diff.split("\n")

      path = ""
      line = ""
      diff_list.each do |source_line|
        case source_line
        when /---\ (a\/)?.*/
          next
        when /\+\+\+\ (b\/)?([^[:blank:]]+).*/
          path = Regexp.last_match(2)
        when /\@\@\ -[0-9]+(,[0-9]+)?\ \+([0-9]+)(,[0-9]+)?\ \@\@.*/
          line = Regexp.last_match(2).to_i
        when /^($esc\[[0-9;]+m)*([\ +-])/
          line += 1 if Regexp.last_match(2) !~ /^-/
          if source_line =~ /^\+/
            @diff_gets << diff_set(path, line, source_line)
          end
        end
      end
    end

    def relation_file
      @diff_gets.each do |diff_get|
        case diff_get[:file]
        when %r{^app\/models}
          method_catch = `sed -n "1,#{diff_get[:no]}p" #{diff_get[:file]} | grep -ni "def " | tail -n 1`

          # 書き換えしたメソッドを判定
          # 判定方法：
          # ファイル内のメソッドと行番号の一覧を検索し、書き換えした行番号と比較、
          # 前にあるメソッドを書き換えたメソッドと判定
          method_name = method_catch.split("def ").last.split("(").first
          if method_name.present?
            # メソッド名で影響しているファイルを検索する。
            # 同じメソッド名が別のファイルでもある場合は検索内容に入る場合がある。
            name = `grep -E "#{method_name}" -rl app | sed 's/ /¥n/g'`
            @relation_files << name.split("\n") if name.present?
          end
          @relation_files << diff_get[:file]
        when %r{^app\/controllers}
          # 取得したい内容
          #  class AssetsApiController < BaseController
          # 取得に省いている内容
          #  authorize_resource :setting, :class => "AndroidSecureSettingGlobalSetting", :parent => false
          #  class InvalidParameterError < StandardError; end
          #  category_class = category.try(:class) || AssetCategory
          method_catch = `sed -n "1,#{diff_get[:no]}p" #{diff_get[:file]} | grep -ni "class [A-Z]" | grep -v " :class" | grep -v "end" | tail -n 1`
          # クラス名のみを取得
          class_name = method_catch.split("class ").last.split(" < ").first
          class_name.split("\n").first
          if class_name == "ApplicationController"
            @relation_files << "全コントローラに影響しています。"

          elsif class_name.present?
            # 継承ファイルを調査
            name = `grep -E "(<.|::)#{class_name}" -rl app/controllers | sed 's/ /¥n/g'`
            @relation_files << name.split("\n") if name.present?
            @relation_files << diff_get[:file]
          else
            @relation_files << diff_get[:file]
          end
        when %r{^app\/views}
          @relation_files << diff_get[:file]
        when %r{^app\/helper}
          method_catch = `sed -n "1,#{diff_get[:no]}p" #{diff_get[:file]} | grep -ni "def " | tail -n 1`
          # 判定方法：
          # ファイル内のメソッドと行番号の一覧を検索し、書き換えした行番号と比較、
          # 前にあるメソッドを書き換えたメソッドと判定
          method_name = method_catch.split("def ").last.split("(").first
          if method_name.present?
            # メソッド名で影響しているファイルを検索する。
            # 同じメソッド名が別のファイルでもある場合は検索内容に入る場合がある。
            name = `grep -E "#{method_name}" -rl  app/views | sed 's/ /¥n/g'`

            @relation_files << name.split("\n") if name.present?
          else
            @relation_files << diff_get[:file]
          end
        when %r{^lib/}
          class_catch = `sed -n "1,#{diff_get[:no]}p" #{diff_get[:file]} | grep -ni "class [A-Z]" | grep -v " :class" | grep -v "end" | tail -n 1`
          # クラス名またはモジュール名を検索
          if class_catch.present?
            class_name = `echo "#{class_catch}" | sed -e "s/^.*class \(.*\) <.*$/\1/"`
          else
            module_catch = `sed -n "1,#{diff_get[:no]}p" #{diff_get[:file]} | grep -ni "module [A-Z]" | tail -n 1`
            class_name = module_catch.split(/(module.|class.)/).last
          end
          class_name = class_name.split("\n").first
          if class_name.present?
            # 継承ファイルを調査
            # 上記で取得したクラス名またはモジュール名の部分一致
            app_name = `grep -E "(extend.|include.|::)#{class_name}" -rl app | sed 's/ /¥n/g'`
            @relation_files << app_name.split("\n") if app_name.present?
            lib_file_name = `grep -E "(extend.|include.|::)#{class_name}" -rl lib | sed 's/ /¥n/g'`
            @relation_files << lib_file_name.split("\n") if lib_file_name.present?
          end
          @relation_files << diff_get[:file]
        else
          @relation_files << diff_get[:file]
        end
      end
      @relation_files.flatten!
      @relation_files.uniq!
    end

    def range_file_value
      file_names = []
      impact_range_yaml = YAML.load_file("script/development/influence_range_file.yml")
      @relation_files.each do |file|
        next unless PICKUP_FILE.include?(file.split("/")[1]) || file.split("/")[0] == "lib"
        path = file.tr("_", "/").tr(".", "/").split("/")
        path.map!(&:singularize)
        key_list = impact_range_yaml.keys
        pickup_key_no = ""

        key_list.each do |key|
          if path.include?(key)
            pickup_key_no = key
            break
          end
        end
        if pickup_key_no.nil?
          impact_range_yaml["name"]
        else
          key_list = impact_range_yaml[pickup_key_no]
        end
        if key_list.class != Hash
          file_names << key_list
          next
        end

        loop do
          key_no_old = pickup_key_no.dup
          key_list.keys.each do |key|
            if path.include?(key)
              pickup_key_no = key
              break
            end
          end
          break if pickup_key_no == key_no_old

          key_list = key_list[pickup_key_no]
          break if key_list.class != Hash
        end

        if key_list.class != Hash
          file_names << key_list
        else
          best_name = key_list["name"]
          file_names << best_name if best_name.present?
        end
      end
      file_names.uniq!
      file_names.compact!
      file_names.sort!.map { |file_name| puts file_name }
    end

    private

    def diff_set(file_name, number, source_line)
      {
        file: file_name,
        no: number,
        line: source_line
      }
    end
  end
end

InfluenceRangeFile.file_list
