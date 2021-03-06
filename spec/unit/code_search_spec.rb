# frozen_string_literal: true

require_relative "../spec_helper.rb"

module SyntaxErrorSearch
  RSpec.describe CodeSearch do
    it "handles no spaces between blocks" do
      search = CodeSearch.new(<<~EOM)
        context "timezones workaround" do
          it "should receive a time in UTC format and return the time with the" do
            travel_to DateTime.new(2020, 10, 1, 10, 0, 0) do
            end
          end
        end
        context "test" do
          it "should" do
        end
      EOM

      search.call

      expect(search.invalid_blocks.join.strip).to eq('it "should" do')
    end

    it "recording" do
      Dir.mktmpdir do |dir|
        dir = Pathname(dir)
        search = CodeSearch.new(<<~EOM, record_dir: dir)
          class OH
            def hello
            def hai
            end
          end
        EOM
        search.call

        expect(search.record_dir.entries.map(&:to_s)).to include("1-add-1.txt")
        expect(search.record_dir.join("1-add-1.txt").read).to eq(<<~EOM.indent(4))
            1  class OH
            2    def hello
          ❯ 3    def hai
          ❯ 4    end
            5  end
        EOM
      end
    end

    it "def with missing end" do
      search = CodeSearch.new(<<~EOM)
        class OH
          def hello

          def hai
            puts "lol"
          end
        end
      EOM
      search.call

      expect(search.invalid_blocks.join.strip).to eq("def hello")

      search = CodeSearch.new(<<~EOM)
        class OH
          def hello

          def hai
          end
        end
      EOM
      search.call

      expect(search.invalid_blocks.join.strip).to eq("def hello")

      search = CodeSearch.new(<<~EOM)
        class OH
          def hello
          def hai
          end
        end
      EOM
      search.call

      expect(search.invalid_blocks.join).to eq(<<~EOM.indent(2))
        def hello
      EOM
    end

    describe "real world cases" do
      it "finds hanging def in this project" do
        source_string = fixtures_dir.join("this_project_extra_def.rb.txt").read
        search = CodeSearch.new(source_string)

        search.call

        blocks = search.invalid_blocks
        io = StringIO.new
        display = DisplayInvalidBlocks.new(
          code_lines: search.code_lines,
          blocks: blocks,
          io: io,
        )
        display.call
        # puts io.string

        expect(display.code_with_lines.strip_control_codes).to include(<<~EOM)
         ❯ 36      def filename
        EOM
      end

      it "Format Code blocks real world example" do
        search = CodeSearch.new(<<~EOM)
          require 'rails_helper'

          RSpec.describe AclassNameHere, type: :worker do
            describe "thing" do
              context "when" do
                let(:thing) { stuff }
                let(:another_thing) { moarstuff }
                subject { foo.new.perform(foo.id, true) }

                it "stuff" do
                  subject

                  expect(foo.foo.foo).to eq(true)
                end
              end
            end # line 16 accidental end, but valid block

              context "stuff" do
                let(:thing) { create(:foo, foo: stuff) }
                let(:another_thing) { create(:stuff) }

                subject { described_class.new.perform(foo.id, false) }

                it "more stuff" do
                  subject

                  expect(foo.foo.foo).to eq(false)
                end
              end
            end # mismatched due to 16
          end
        EOM
        search.call

        blocks = search.invalid_blocks
        io = StringIO.new
        display = DisplayInvalidBlocks.new(
          io: io,
          blocks: blocks,
          code_lines: search.code_lines,
          filename: "fake/spec/lol.rb"
        )
        display.call
        # io.string

        expect(display.code_with_lines).to include(<<~EOM)
             1  require 'rails_helper'
             2
             3  RSpec.describe AclassNameHere, type: :worker do
          ❯  4    describe "thing" do
          ❯ 16    end # line 16 accidental end, but valid block
          ❯ 30    end # mismatched due to 16
            31  end
        EOM
      end
    end


    # For code that's not perfectly formatted, we ideally want to do our best
    # These examples represent the results that exist today, but I would like to improve upon them
    describe "needs improvement" do
      describe "missing describe/do line" do
        it "blerg" do
          # code_lines = code_line_array fixtures_dir.join("this_project_extra_def.rb.txt").read
          # block = CodeBlock.new(
          #   lines: code_lines[31],
          #   code_lines: code_lines
          # )
          # expect(block.to_s).to eq(<<~EOM.indent(8))
          #   \#{code_with_filename}
          # EOM

          # puts    block.before_line.to_s.inspect
          # puts    block.before_line.to_s.split(/\S/).inspect
          # puts    block.before_line.indent

          # puts    block.after_line.to_s.inspect
          # puts    block.after_line.to_s.split(/\S/).inspect
          # puts    block.after_line.indent

          # puts block.expand_until_next_boundry
        end
      end

      describe "mis-matched-indentation" do
        it "extra space before end" do
          search = CodeSearch.new(<<~EOM)
            Foo.call
              def foo
                puts "lol"
                puts "lol"
               end # one
            end # two
          EOM
          search.call

          expect(search.invalid_blocks.join).to eq(<<~EOM)
            Foo.call
            end # two
          EOM
        end

        it "stacked ends 2" do
          search = CodeSearch.new(<<~EOM)
            def lol
              blerg
            end

            Foo.call do
            end # one
            end # two

            def lol
            end
          EOM
          search.call

          expect(search.invalid_blocks.join).to eq(<<~EOM)
            Foo.call do
            end # one
            end # two

          EOM
        end

        it "stacked ends " do
          search = CodeSearch.new(<<~EOM)
            Foo.call
              def foo
                puts "lol"
                puts "lol"
            end
            end
          EOM
          search.call

          expect(search.invalid_blocks.join).to eq(<<~EOM)
            Foo.call
            end
          EOM
        end

        it "missing space before end" do
          search = CodeSearch.new(<<~EOM)
            Foo.call

              def foo
                puts "lol"
                puts "lol"
             end
            end
          EOM
          search.call

          # expand-1 and expand-2 seem to be broken?
          expect(search.invalid_blocks.join).to eq(<<~EOM)
            Foo.call
            end
          EOM
        end
      end
    end

    it "returns syntax error in outer block without inner block" do
      search = CodeSearch.new(<<~EOM)
        Foo.call
          def foo
            puts "lol"
            puts "lol"
          end # one
        end # two
      EOM
      search.call

      expect(search.invalid_blocks.join).to eq(<<~EOM)
        Foo.call
        end # two
      EOM
    end

    it "doesn't just return an empty `end`" do
      search = CodeSearch.new(<<~EOM)
        Foo.call
        end
      EOM
      search.call

      expect(search.invalid_blocks.join).to eq(<<~EOM)
        Foo.call
        end
      EOM
    end

    it "finds multiple syntax errors" do
      search = CodeSearch.new(<<~EOM)
        describe "hi" do
          Foo.call
          end
        end

        it "blerg" do
          Bar.call
          end
        end
      EOM
      search.call

      expect(search.invalid_blocks.join).to eq(<<~EOM.indent(2))
          Foo.call
          end
          Bar.call
          end
      EOM
    end

    it "finds a typo def" do
      search = CodeSearch.new(<<~EOM)
        defzfoo
          puts "lol"
        end
      EOM
      search.call

      expect(search.invalid_blocks.join).to eq(<<~EOM)
        defzfoo
        end
      EOM
    end

    it "finds a mis-matched def" do
      search = CodeSearch.new(<<~EOM)
        def foo
          def blerg
        end
      EOM
      search.call

      expect(search.invalid_blocks.join).to eq(<<~EOM.indent(2))
        def blerg
      EOM
    end

    it "finds a naked end" do
      search = CodeSearch.new(<<~EOM)
        def foo
          end
        end
      EOM
      search.call

      expect(search.invalid_blocks.join).to eq(<<~EOM.indent(2))
        end
      EOM
    end

    it "returns when no invalid blocks are found" do
      search = CodeSearch.new(<<~EOM)
        def foo
          puts 'lol'
        end
      EOM
      search.call

      expect(search.invalid_blocks).to eq([])
    end

    it "expands frontier by eliminating valid lines" do
      search = CodeSearch.new(<<~EOM)
        def foo
          puts 'lol'
        end
      EOM
      search.add_invalid_blocks

      expect(search.code_lines.join).to eq(<<~EOM)
        def foo
        end
      EOM
    end
  end
end
