module GnuplotUtils

  using Dates
  using Printf
  using Base64
  using IOCapture
  using ColorSchemes
  using Gnuplot

  export @gnuplot_quote_str, @gnuplot_str

  abstract type GPAbstractData end
  abstract type GPAbstractDataFile <: GPAbstractData end

  const options = Gnuplot.options
  const default = Dict(
     :timefmt => "%s",
  )

  gnuplot_session = nothing
  verbose_mode    = false
  datablock_count = 10000
  array_count = 10000
  current_terminal = "unknown"
  current_termoption = ""
  current_output   = nothing
  in_multiplot = false
  plot_mode   = nothing
  plot_stack  = Array{String}(undef,0)
  splot_stack = Array{String}(undef,0)
  temporary_data = Array{GPAbstractData}(undef,0)

  include("dataset.jl")

  #
  #
  #
  function load(filename::String)
    put("load \"$filename\"")
  end

  function viewer(b::Bool)
    options.gpviewer = b
  end

  function verbose(b::Bool=true)
    GnuplotUtils.verbose_mode = b
  end

  #
  # GnuplotUtils.put()
  #
  
  import Base.show

  struct PlotImage{format}
    data::String
  end

  function html_img_encoded(io, mime::String, data::String)
    write(io, "<img src=\"data:$mime;base64,")
    io64 = Base64EncodePipe(io)
    write(io64, data)
    close(io64)
    write(io, "\" />")
    nothing
  end

  Base.show(io::IO, ::MIME"text/plain", img::PlotImage{:dumb})    = write(io, img.data)
  Base.show(io::IO, ::MIME"text/plain", img::PlotImage{:block})   = write(io, img.data)
  Base.show(io::IO, ::MIME"image/png", img::PlotImage{:pngcairo}) = write(io, img.data)
  Base.show(io::IO, ::MIME"image/png", img::PlotImage{:png})      = write(io, img.data)
  Base.show(io::IO, ::MIME"image/jpeg", img::PlotImage{:jpeg})    = write(io, img.data)
  Base.show(io::IO, ::MIME"image/svg+xml", img::PlotImage{:svg})  = write(io, img.data)
  Base.show(io::IO, ::MIME"text/html", img::PlotImage{:gif})      = html_img_encoded(io, "image/gif", img.data)
  Base.show(io::IO, ::MIME"text/html", img::PlotImage{:webp})     = html_img_encoded(io, "image/webp", img.data)

  function put(obj::String)
    global gnuplot_session
    if isnothing(gnuplot_session)
      gnuplot_session = Gnuplot.getsession(options.default)
      reset()
    end
    try
      if options.gpviewer || ! occursin(r"^\s*(plot|splot|replot)\s+"m, obj)
        (GnuplotUtils.verbose_mode) && println(chomp(obj))
        out = Gnuplot.gpexec(gnuplot_session, obj)
        if GnuplotUtils.verbose_mode && ( ! isempty(out) )
          for line in eachline(IOBuffer(out*"\n"))
            println("#--- " * line)
          end
        end
        return out
      else
        c = IOCapture.capture() do
          Gnuplot.gpexec(gnuplot_session, obj)
          return nothing
        end
        return PlotImage{current_terminal}(c.output)
      end
    catch e
      Gnuplot.gpexec(gnuplot_session, "reset error")
      try
        Gnuplot.options.verbose = true
        Gnuplot.gpexec(gnuplot_session, obj)
      catch
      finally
        Gnuplot.options.verbose = false
      end
      rethrow(e)
    end
  end

  function put(obj::GPDataArray)
    return put(obj())
  end

  function put(obj::GPAbstractDataFile)
    put("print 'setting data'")
    return nothing
  end

  macro gnuplot_quote_str(ex)
    ex = replace(ex, r"\$([\d\#])"=>s"\\$\1")
    s = Meta.parse("\"\"\""*ex*"\"\"\"")
    esc(:(eval($s)))
  end

  macro gnuplot_str(ex)
    ex = replace(ex, r"\$([\d\#])"=>s"\\$\1")
    s = Meta.parse("\"\"\""*ex*"\"\"\"")
    esc(:(GnuplotUtils.put(eval($s))))
  end

  #
  # GnuplotUtils.set()
  #
  function set(args::Vararg{String})
    for option in args
      put("set $option")
    end
  end

  #
  # GnuplotUtils.unset()
  #
  function unset(args::Vararg{String})
    for option in args
      put("set $option")
    end
  end

  #
  # plot
  #

  function plot(spec::String)
    command = ""
    if isnothing(GnuplotUtils.plot_mode)
      GnuplotUtils.plot_mode = :plot
      command *= "plot "
    elseif GnuplotUtils.plot_mode != :plot
      error("do not mix plot and splot")
    end
    command *= spec
    return push!(GnuplotUtils.plot_stack, command)    
  end

  function plot(obj::GPAbstractData, option::String = "")
    return plot("$obj $option")
  end

  function plot(args::Tuple, option::String = "") 
    types = [eltype(a) for a in args]
    list  = collect(args)
    maxlen = minimum(map(x->length(x), list))
    has_string = false
    has_date   = false
    for k in 1:length(list)
      if types[k] ∈ (DateTime, Date, Time)
        has_date = true
        list[k] = datetime2unix.(list[k])
      end
      if types[k] == String
        has_string = true
      end
    end
    if has_string || maxlen < 50
      obj = inline(list...)
    else
      obj = binary(list...)
    end
    push!(GnuplotUtils.temporary_data, obj)
    if has_date
      set("timefmt '%s'")
    end
    return plot("$obj $option")
  end

  #
  # splot
  #

  function splot(spec::String)
    command = ""
    if isnothing(GnuplotUtils.plot_mode)
      GnuplotUtils.plot_mode = :splot
      command *= "splot "
    elseif GnuplotUtils.plot_mode != :splot
      error("do not mix plot and splot")
    end
    command *= spec
    return push!(GnuplotUtils.splot_stack, command)
  end

  function splot(obj::GPAbstractData, option::String = "")
    return splot("$obj $option")
  end

  function splot(args::Tuple, option::String = "") 
    types = [eltype(a) for a in args]
    list  = collect(args)
    has_string = false
    has_date   = false
    for k in 1:length(list)
      if types[k] ∈ (DateTime, Date, Time)
        has_date = true
        list[k] = datetime2unix.(list[k])
      end
      if types[k] == String
        has_string = true
      end
    end
    if has_string
      obj = inline(list...)
    else
      obj = binary(list...)
    end
    push!(GnuplotUtils.temporary_data, obj)
    if has_date
      set("timefmt '%s'")
    end
    return splot("$obj $option")
  end

  #
  # flush
  #

  function flush()
    try
      if isnothing(GnuplotUtils.plot_mode)
        return 
      elseif GnuplotUtils.plot_mode == :plot
        return put(join(GnuplotUtils.plot_stack,",\\\n"))
      elseif GnuplotUtils.plot_mode == :splot
        return put(join(GnuplotUtils.splot_stack,",\\\n"))
      end
    finally
      GnuplotUtils.plot_mode = nothing
      empty!(GnuplotUtils.plot_stack)
      empty!(GnuplotUtils.splot_stack)
    end  
  end

  #
  # GnuplotUtils.terminal()
  # GnuplotUtils.output()
  #

  function terminal(term::Symbol, option::String="")
    global current_terminal = term
    global current_termoption = option
    return put("set terminal $term $option")
  end

  function output(filename::Union{String,Nothing})
    if isnothing(filename)
      current_output = nothing
      set("output")
    else
      current_output = filename
      set("output \"$filename\"")
    end
  end


  #
  # FIXME: savefig
  #
  function guess_terminal(filename::String)
    if occursin(r"\.png$"i, filename)
      return :pngcairo
    elseif occursin(r"\.pdf$"i, filename)
      return :pdfcairo
    elseif occursin(r"\.svg$"i, filename)
      return :svg
    else
      error("unknown output file format (only png,pdf,svg are supported)")
    end    
  end

  function savefig(::Nothing)
    global current_terminal
    Gnuplot.gpexec(gnuplot_session, "set output")                
    c = IOCapture.capture() do
      Gnuplot.gpexec(gnuplot_session, "replot")
      return nothing
    end
    if options.gpviewer 
      return c.output
    else
      return PlotImage{current_terminal}(c.output)
    end
  end

  function savefig(filename::String)
    try
      Gnuplot.gpexec(gnuplot_session, "set output '$filename'")    
      Gnuplot.gpexec(gnuplot_session, "replot")
    finally
      Gnuplot.gpexec(gnuplot_session, "set output")
    end
  end

  function savefig(filename::Union{String,Nothing}, term::Symbol, option::String="")
    global current_terminal
    global current_termoption
    saved_terminal = current_terminal
    saved_termoption = current_termoption
    try
      terminal(term, option)
      return savefig(filename)
    finally
      terminal(saved_terminal, saved_termoption)
    end
  end

  function savefig(filename::String, option::String)
    terminal = guess_terminal(filename)
    return savefig(filename, terminal, option)
  end

  function savefig(term::Symbol, option::String="")
    return savefig(nothing, term, option)
  end

  function savefig()
    return savefig(nothing)
  end

  #
  # pause
  #

  function pause(nsec = -1)
    if options.gpviewer 
      if nsec < 0
        return readline()
      else
        sleep(nsec)
      end
    end
  end

  function pause(option::String)
    return put("pause $option")
  end

  #
  # reset
  #

  reset_commands = nothing

  function reset()
    empty!(GnuplotUtils.plot_stack)
    empty!(GnuplotUtils.splot_stack)
    if ! isempty(GnuplotUtils.temporary_data)
      for obj in GnuplotUtils.temporary_data
        undefine(obj)
      end
      empty!(GnuplotUtils.temporary_data)
    end
    if GnuplotUtils.in_multiplot
      reset_in_multiplot()
    else
      reset_outside_multiplot()
    end
  end

  function reset_outside_multiplot()
    global default
    put("""
        reset
        set xyplane relative 0
        set key Left reverse noautotitle
        unset object
        unset arrow
        unset label
        """)
    for (key, value) in default
      set_default(Val(Symbol(key)), value)
    end
  end

  function reset_in_multiplot()
    global reset_commands
    if isnothing(reset_commands)
      open(`gnuplot -e "save set '-'"`) do io
        list = readlines(io)
        for k in axes(list,1)
          occursin(r"^set size ratio",   list[k]) && (list[k] = ""; continue)
          occursin(r"^set origin",       list[k]) && (list[k] = ""; continue)
          occursin(r"^set [lrtb]margin", list[k]) && (list[k] = ""; continue)
          occursin(r"^set locale",       list[k]) && (list[k] = ""; continue)
          occursin(r"^set decimalsign",  list[k]) && (list[k] = ""; continue)
          occursin(r"^set encoding",     list[k]) && (list[k] = ""; continue)
          occursin(r"^set loadpath",     list[k]) && (list[k] = ""; continue)
          occursin(r"^set fontpath",     list[k]) && (list[k] = ""; continue)
          occursin(r"^set psdir",        list[k]) && (list[k] = ""; continue)
          occursin(r"^sset fit",         list[k]) && (list[k] = ""; continue)
        end
        reset_commands = join(list, "\n")
      end 
    end
    put(reset_commands)
  end

  #
  # multiplot
  #

  function multiplot(block::Function, option)
    try
      put("set multiplot " * option)
      GnuplotUtils.in_multiplot = true
      block()
    finally
      put("unset multiplot")  
      GnuplotUtils.in_multiplot = false
    end
  end

  #
  # palette
  #

  function palette(name; maxcolors = nothing)
    cs = colorschemes[name]
    colors = String[]
    for i in range(0, 1, length=length(cs))
      c = get(cs, i)
      push!(colors, "$i $(c.r) $(c.g) $(c.b)")
    end
    set("palette defined ("*join(colors, ", ") * ")")
    if ! isnothing(maxcolors) 
      set("palette maxcolors $maxcolors")
    end
  end

  #
  # set_default
  #

  function set_default(::Val{:timefmt}, format_string)
    set("timefmt '$format_string'")
  end

  #
  # set_default
  #

  function axis()
    
  end
    
end


