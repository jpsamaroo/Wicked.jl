module Wicked

### Imports ###

using VT100
import VT100: Cell

### Exports ###

export Panel, PanelIO

### Types ###

"""
    Panel

A representation of a drawable terminal surface.
"""
struct Panel
  data::Matrix{Cell}
end

"""
    PanelIO <: IO

An IO object that can parse terminal input (including control codes) and store
them represented as a `Matrix` of `VT100.Cell`s. See `VT100.ScreenEmulator`
for details on the backend's capabilities.

Note: `PanelIO` epresents sizes and indices in (height, width) format, whereas
`VT100.ScreenEmulator` takes sizes as (width, height).
"""
struct PanelIO <: IO
  screen::ScreenEmulator
end
PanelIO(height, width) = PanelIO(ScreenEmulator(width, height))
function Panel(io::PanelIO)
  panel = Panel(undef, size(io)...)
  for h in 1:size(io)[1]
    for w in 1:size(io)[2]
      panel[h,w] = io[h,w]
    end
  end
  panel
end

### Methods ###

Base.size(panel::Panel) = size(panel.data)
Base.size(io::PanelIO) =
  (io.screen.ViewPortSize.height, io.screen.ViewPortSize.width)

function Base.getindex(io::PanelIO, row::Int, col::Int)
  se = io.screen
  height, width = size(io)
  @assert 1 <= row <= height "Invalid row index: $row"
  @assert 1 <= col <= width "Invalid col index: $col"
  if length(se.lines.data) >= row
    if length(se.lines[row].data) >= col
      return se.lines[row][col]
    end
  end
  return Cell(' ')
end

function Base.print(io::PanelIO, x::Union{SubString{String}, String})
  iob = IOBuffer(modified_parse(string(x)))
  parseall!(io.screen, iob)
end
# TODO: Just manually copy cells into io's buffer
function Base.print(io::PanelIO, panel::Panel)
  iob = IOBuffer()
  for cell in panel.data
    cell_dump!(iob, cell)
  end
  print(io, String(take!(iob)))
end
function Base.write(io::PanelIO, x::UInt8)
  # TODO: Manually handle the case where x is '\n'
  parseall!(io.screen, IOBuffer(modified_parse(string(Char(x)))))
  return 1
end

# TODO: This probably shouldn't reset the cursor to top-left
# TODO: since this might be used for display in the REPL
function Base.show(io::IO, panel::Panel)
  print(io, "\e[1;1H")
  iob = IOBuffer()
  panel_dump!(iob, panel)
  print(io, String(take!(iob)))
end

"Appends a terminal-parseable representation of `panel` into `iob`"
function panel_dump!(iob::IOBuffer, panel::Panel)
  height, width = size(panel.data)
  for h in 1:height
    print(iob, "\e[s")
    for w in 1:width
      cell_dump!(iob, panel.data[h,w])
      print(iob, "\e[0m")
    end
    print(iob, "\e[u\e[B")
  end
end

"Appends a terminal-parseable representation of `cell` into `iob`"
function cell_dump!(iob::IOBuffer, cell::Cell)
  # FIXME: More attrs
  if cell.attrs & VT100.Attributes.Blink > 0
    print(iob, "\e[5m")
  end
  if cell.flags & VT100.Flags.FG_IS_RGB > 0
    r = Int(floor(cell.fg_rgb.r*255))
    b = Int(floor(cell.fg_rgb.g*255))
    g = Int(floor(cell.fg_rgb.b*255))
    print(iob, "\e[38;2;$(r);$(g);$(b)m")
  elseif cell.flags & VT100.Flags.FG_IS_256 > 0
    if 0 <= cell.fg <= 7
      print(iob, "\e[3$(string(cell.fg))m")
    elseif 8 <= cell.fg <= 15
      print(iob, "\e[9$(string(cell.fg-8))m")
    else
      print(iob, "\e[38;5;$(string(cell.fg))m")
    end
  else
    print(iob, "\e[39m")
  end

  if cell.flags & VT100.Flags.BG_IS_RGB > 0
    r = Int(floor(cell.bg_rgb.r*255))
    b = Int(floor(cell.bg_rgb.g*255))
    g = Int(floor(cell.bg_rgb.b*255))
    print(iob, "\e[48;2;$(r);$(g);$(b)m")
  elseif cell.flags & VT100.Flags.BG_IS_256 > 0
    if 0 <= cell.bg <= 7
      print(iob, "\e[4$(string(cell.bg))m")
    elseif 8 <= cell.bg <= 15
      print(iob, "\e[10$(string(cell.bg-8))m")
    else
      print(iob, "\e[48;5;$(string(cell.bg))m")
    end
  else
    print(iob, "\e[49m")
  end

  print(iob, cell.content)
end

"""Returns a new `Panel` resized to the desired height and width. If a
dimension is extended, fills those `Cell`s with `fill_value`."""
function resize_panel(panel::Panel, new_size::Tuple{Int,Int},
    fill_value=Cell(' '))
  old_size = size(panel)
  old_size == new_size && return panel
  new_panel = fill(fill_value, new_size)
  shared_region = CartesianIndices(min.(old_size, new_size))
  copy!(new_panel, shared_region, panel, shared_region)
end

"Prepends carriage returns to newlines in a string."
# TODO: Add method for ::IO argument
function modified_parse(str::String)
  retstr = ""
  for char in str
    if char == '\n'
      retstr *= '\r'
    end
    retstr *= char
  end
  retstr
end

end # module
