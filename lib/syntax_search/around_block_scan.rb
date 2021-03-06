# frozen_string_literal: true
#
module SyntaxErrorSearch
  # This class is useful for exploring contents before and after
  # a block
  #
  # It searches above and below the passed in block to match for
  # whatever criteria you give it:
  #
  # Example:
  #
  #   def dog
  #     puts "bark"
  #     puts "bark"
  #   end
  #
  #   scan = AroundBlockScan.new(
  #     code_lines: code_lines
  #     block: CodeBlock.new(lines: code_lines[1])
  #   )
  #
  #   scan.scan_while { true }
  #
  #   puts scan.before_index # => 0
  #   puts scan.after_index # => 3
  #
  # Contents can also be filtered using AroundBlockScan#skip
  #
  # To grab the next surrounding indentation use AroundBlockScan#scan_adjacent_indent
  class AroundBlockScan
    def initialize(code_lines: , block:)
      @code_lines = code_lines
      @orig_before_index = block.lines.first.index
      @orig_after_index = block.lines.last.index
      @orig_indent = block.current_indent
      @skip_array = []
      @after_array = []
      @before_array = []
      @stop_after_kw = false
    end

    def skip(name)
      @skip_array << name
      self
    end

    def stop_after_kw
      @stop_after_kw = true
      self
    end

    def scan_while(&block)
      stop_next = false

      kw_count = 0
      end_count = 0
      @before_index = before_lines.reverse_each.take_while do |line|
        next false if stop_next
        next true if @skip_array.detect {|meth| line.send(meth) }

        kw_count += 1 if line.is_kw?
        end_count += 1 if line.is_end?
        if @stop_after_kw && kw_count > end_count
          stop_next = true
        end

        block.call(line)
      end.reverse.first&.index

      stop_next = false
      kw_count = 0
      end_count = 0
      @after_index = after_lines.take_while do |line|
        next false if stop_next
        next true if @skip_array.detect {|meth| line.send(meth) }

        kw_count += 1 if line.is_kw?
        end_count += 1 if line.is_end?
        if @stop_after_kw && end_count > kw_count
          stop_next = true
        end

        block.call(line)
      end.last&.index
      self
    end

    def scan_neighbors
      self.scan_while {|line| line.not_empty? && line.indent >= @orig_indent }
    end

    def scan_adjacent_indent
      before_indent = @code_lines[@orig_before_index.pred]&.indent || 0
      after_indent = @code_lines[@orig_after_index.next]&.indent || 0


      indent = [before_indent, after_indent].min
      self.scan_while {|line| line.not_empty? && line.indent >= indent }

      self
    end

    def code_block
      CodeBlock.new(lines: @code_lines[before_index..after_index])
    end

    def before_index
      @before_index || @orig_before_index
    end

    def after_index
      @after_index || @orig_after_index
    end

    private def before_lines
      @code_lines[0...@orig_before_index]
    end

    private def after_lines
      @code_lines[@orig_after_index.next..-1]
    end
  end
end
