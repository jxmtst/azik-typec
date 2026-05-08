require 'io/console'
require 'unicode/display_width'

module Azik
  module TUI
    CSI = "\e["

    module_function

    def with_raw_mode
      $stdin.raw do |io|
        print "#{CSI}?25l"
        yield io
      ensure
        print "#{CSI}?25h"
        print "\n"
      end
    end

    def clear_screen
      print "#{CSI}2J#{CSI}H"
    end

    def move(row, col)
      print "#{CSI}#{row};#{col}H"
    end

    def color(text, code)
      "#{CSI}#{code}m#{text}#{CSI}0m"
    end

    def read_key(io)
      ch = io.getc
      return nil if ch.nil?
      if ch == "\e"
        begin
          seq = io.read_nonblock(4)
          return "\e#{seq}"
        rescue IO::WaitReadable, EOFError
          return "\e"
        end
      end
      ch
    end

    def display_width(s)
      Unicode::DisplayWidth.of(s)
    end
  end
end
