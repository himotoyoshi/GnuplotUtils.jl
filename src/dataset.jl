#
# internal
#   obj2text(obj)
#
# Converts an object to a string
#
function obj2text(obj::String)
  return "\""*obj*"\""
end

function obj2text(obj::Missing)
  return "?"
end

function obj2text(obj::TimeType)
  return string(datetime2unix(obj))
end

function obj2text(obj)
  return string(obj)
end

#
# Array
# 
struct GPDataArray <: GPAbstractData
  name::String
  
  function GPDataArray(ary::AbstractVector)
    global array_count
    try
      obj = new("AR" * string(array_count))
      put("array " * 
           obj.name * "[" * string(length(ary)) * "] = [\\\n" *
           join(obj2text(ary), ",\\\n") * "]")
      return obj
    finally
      array_count += 1
    end
  end

end

Base.print(io::IO, obj::GPDataArray) = Base.print(io, obj.name)

#
# internal
#   to_textdata(args...)
#
# Converts objects (Vector or Matrix) to a string
#

function to_textdata(args::Vararg{AbstractVector, N}; option=option) where N
  len = length(args[1])
  io  = IOBuffer()
  for i=1:len
    print(io, join([obj2text(args[k][i]) for k=1:N], " "), "\n")
  end
  return (String(take!(io)), option)
end

function to_textdata(args::Vararg{AbstractMatrix, N}; option=option) where N
  dims = size(args[1])
  io   = IOBuffer()
  if N == 1
    print(io, obj2text(dims[1]))
    for j=1:dims[1]
      print(io, " " * obj2text(j))
    end
    print(io, "\n")
    for i=1:dims[2]
      print(io, obj2text(i))
      for j=1:dims[1]
        print(io, " " * obj2text(args[1][j,i]))
      end
      print(io, "\n")
    end
    option = " nonuniform matrix $option "
  else
    for i=1:dims[1] 
      for j=1:dims[2]
        print(io, join([obj2text(args[k][j,i]) for k=1:N], " "), "\n")
      end
      print(io, "\n")
    end
  end
  return (String(take!(io)), option)
end

function to_textdata(v1::T, v2::T, mtx1::AbstractMatrix, mtxs::Vararg{AbstractMatrix, N}; option=option) where {T <: AbstractVector, N}
  args = (mtx1, mtxs...)
  n = length(args)
  dims = (length(v2), length(v1))
  io = IOBuffer()
  if N == 1
    print(io, obj2text(dims[1]))
    for j=1:dims[1]
      print(io, " " * obj2text(v2[j]))
    end
    print(io, "\n")
    for i=1:dims[2]
      print(io, obj2text(v1[i]))
      for j=1:dims[1]
        print(io, " " * obj2text(args[1][j,i]))
      end
      print(io, "\n")
    end
    option = " nonuniform matrix $option "
  else
    for i=1:dims[2]
      for j=1:dims[1]
        print(io, obj2text(v1[i]), " ", obj2text(v2[j]), " ", 
                  join([obj2text(args[k][j,i]) for k=1:n], " "), "\n")
      end
      print(io, "\n")
    end
  end
  return (String(take!(io)), option)
end

#
#
#
struct GPDataBlock <: GPAbstractData
  name::String
  option::String
  
  function GPDataBlock(; option="")
    global datablock_count
    try
      return new("\$DB" * string(datablock_count), option)
    finally
      datablock_count += 1
    end
  end

  function GPDataBlock(data::String; option="")
    obj = GPDataBlock(option=option)
    put(obj.name * " <<EOD\n" * chomp(data) * "\nEOD\n")
    return obj
  end

  function GPDataBlock(block::Function; option="")
    obj = GPDataBlock(option=option)
    io = IOBuffer()
    block(io)
    seekstart(io)
    put(obj.name * " <<EOD\n" * chomp(read(io, String)) * "\nEOD\n")
    return obj
  end

  function GPDataBlock(args...; option="")
    obj = GPDataBlock()
    data, option = to_textdata(args..., option=option)
    put(obj.name * " <<EOD\n" * data * "\nEOD\n")
    return obj
  end

  function GPDataBlock(v::T, fn1::Function, fns::Vararg{Function, N}; option="") where {T <: AbstractVector, N}
    args = (fn1, fns...)
    args = map((f)->(f.(v)), args)
    return GPDataBlock(v, args...; option=option)
  end

  function GPDataBlock(v1::T, v2::T, arg1::Function, fns::Vararg{Function, N}; option="") where {T <: AbstractVector, N}
    args = (fn1, fns...)
    args = map((f)->(f.(v1',v2)), args)
    return GPDataBlock(v1, v2, args...; option=option)
  end

end

Base.print(io::IO, obj::GPDataBlock) = Base.print(io, obj.name)

struct GPDataFile <: GPAbstractDataFile
  file::String
  type::String
  option::String

  function GPDataFile(; option="")
    (path, io) = mktemp()
    close(io)
    return new(path)
  end

  function GPDataFile(block::Function; option="")
    obj = GPDataFile(option=option)
    open(obj.file, "a") do io
      block(io)
    end
    return obj
  end

  function GPDataFile(args...; option="")
    obj = GPDataFile(option=option)
    data, option = to_textdata(args..., option=option)
    open(obj.file, "a") do io
      write(io, data)
    end
    return obj
  end
end

Base.print(io::IO, obj::GPDataFile) = Base.print(io, " \"" * obj.file * "\" volatile ")

table_eltype2format = Dict(
  Float64 => "%float64",
  Float32 => "%float32",
  Int8 => "%int8",
  UInt8 => "%uint8",
  Int16 => "%int16",
  UInt16 => "%uint16",
  Int32 => "%int32",
  UInt32 => "%uint32",
  Int64 => "%int64",
  UInt64 => "%uint64",
  Date => "%float64",
  Time => "%float64",
  DateTime => "%float64",
)

function eltype2format(ary::AbstractArray)
  global table_eltype2format
  return table_eltype2format[eltype(ary)]
end

function to_number(v)
  return v
end

function to_number(v::Missing)
  return NaN
end

function to_number(v::TimeType)
  return datetime2unix(v)
end

function to_binarydata(args::Vararg{AbstractVector, N}; option="") where N
  len = length(args[1])
  if any([length(args[k]) != len for k=1:N])
    error("dimension mismatch in given vectors")
  end
  io = IOBuffer()
  for i=1:len, k=1:N
    write(io, to_number(args[k][i]))
  end
  format = join([eltype2format(args[k]) for k=1:N],"")
  spec = "binary record=$(len) $option format='" * format * "'"
  return (String(take!(io)), spec)
end

function to_binarydata(args::Vararg{AbstractMatrix, N}; option="") where N
  dims = size(args[1])
  if any([size(args[k]) != dims for k=1:N])
    error("dimension mismatch in given vectors")
  end
  io = IOBuffer()
  for i=1:dims[2], j=1:dims[1], k=1:N
    write(io, to_number(args[k][j,i]))
  end
  format = join([eltype2format(args[k]) for k=1:N],"")
  spec = "binary record=(" * join(string.(dims), ", ") * ") $option " * 
                                      "format='" * format * "'"    
  return (String(take!(io)), spec)
end

function to_binarydata(v1::T, v2::T, mtx1::AbstractMatrix, mtxs::Vararg{AbstractMatrix, N}; option="") where {T <: AbstractVector, N}  
  args = (mtx1, mtxs...)
  n = length(args)
  dims = (length(v2), length(v1))
  if any([size(args[k]) != dims for k=1:n])
    error("dimension mismatch in given vectors")
  end
  io = IOBuffer()
  for i=1:dims[2], j=1:dims[1]
    write(io, to_number(v1[i]), to_number(v2[j]))
    for k=1:n
      write(io, to_number(args[k][j,i]))
    end
  end
  format = eltype2format(v1) * eltype2format(v2) *
                  join([eltype2format(args[k]) for k=1:n],"")
  spec = "binary record=(" * join(string.(dims), ", ") * ") $option " *
                                                  "format='" * format * "' "
  return (String(take!(io)), spec)
end

struct GPDataBinary <: GPAbstractDataFile
  file::String
  source::String

  function GPDataBinary(args...; option="")
    data, spec = to_binarydata(args...; option=option)
    (file, io) = mktemp()
    write(io, data)
    close(io)
    return new(file, " '$file' volatile $spec ")
  end

  function GPDataBinary(v::T, fn1::Function, fns::Vararg{Function, N}; option="") where {T <: AbstractVector, N}
    args = (fn1, fns...)
    args = map((f)->(f.(v)), args)
    return GPDataBinary(v, args...; option=option)
  end

  function GPDataBinary(v1::T, v2::T, fn1::Function, fns::Vararg{Function, N}; option="") where {T <: AbstractVector, N}
    args = (fn1, fns...)
    args = map((f)->(f.(v1',v2)), args)
    return GPDataBinary(v1, v2, args...; option=option)
  end
    
end

Base.print(io::IO, obj::GPDataBinary) = Base.print(io, obj.source)

function to_float32(v::Float32)
  return v
end

function to_float32(v::Missing)
  return NaN32
end

function to_float32(v::TimeType)
  return datetime2unix(v)
end

function to_float32(v)
  return Float32(v)
end

function to_imagedata_single(mtx::Matrix{Float32}) 
  dims = size(mtx)
  io = IOBuffer()
  write(io, to_float32(dims[1]))
  for j=1:dims[1]
    write(io, Float32(j))
  end
  for i=1:dims[2]
    write(io, Float32(i))
    for j=1:dims[1]
      write(io, mtx[j,i])
    end
  end
  spec = "matrix binary"        
  return (String(take!(io)), "")
end

function to_imagedata_single(mtx::AbstractMatrix)
  dims = size(mtx)
  io = IOBuffer()
  write(io, to_float32(dims[1]))
  for j=1:dims[1]
    write(io, to_float32(j))
  end
  for i=1:dims[2]
    write(io, to_float32(i))
    for j=1:dims[1]
      write(io, to_float32(mtx[j,i]))
    end
  end
  spec = "matrix binary"
  return (String(take!(io)), "")
end

function to_imagedata(args::Vararg{AbstractMatrix, N}; option="") where N
  if N == 1 && isempty(option)
    return to_imagedata_single(args[1])
  end
  dims = size(args[1])
  if any([size(args[k]) != dims for k=1:N])
    error("dimension mismatch in given vectors")
  end
  io = IOBuffer()
  v1 = Float32.(1:dims[1])
  v2 = Float32.(1:dims[2])
  for i=1:dims[2], j=1:dims[1]
    for k=1:N
      write(io, args[k][j,i])
    end
  end
  format = join([eltype2format(args[k]) for k=1:N],"")
  spec = "binary array=(" * join(string.(dims), ", ") * ") $option " * 
                                      "format='" * format * "'"    
  return (String(take!(io)), spec)
end

function to_imagedata_single(v1::T, v2::T, mtx::AbstractMatrix; option="") where T <: AbstractVector  
  dims = (length(v2), length(v1))
  if size(mtx) != dims
    error("dimension mismatch in given vectors")
  end
  io = IOBuffer()
  write(io, to_float32(dims[1]))
  for j=1:dims[1]
    write(io, to_float32(v2[j]))
  end
  for i=1:dims[2]
    write(io, to_float32(v1[i]))
    for j=1:dims[1]
      write(io, to_float32(mtx[j,i]))
    end
  end
  spec = "binary matrix $option "        
  return (String(take!(io)), spec)
end

function to_imagedata(v1::T, v2::T, args::Vararg{AbstractMatrix, N}; option="") where {T <: AbstractVector, N}
  if N == 1 && isempty(option)
    return to_imagedata_single(v1, v2, args[1])
  end
  dims = (length(v2), length(v1))
  if any([size(args[k]) != dims for k=1:N])
    error("dimension mismatch in given vectors")
  end
  v1 = Float32.(v1)
  v2 = Float32.(v2)
  io = IOBuffer()
  for i=1:dims[2], j=1:dims[1]
    write(io, v1[i], v2[j])
    for k=1:N
      write(io, args[k][j,i])
    end
  end
  format = "%float32%float32" * join([eltype2format(args[k]) for k=1:N],"")
  spec = "binary record=(" * join(string.(dims), ", ") * ") $option " * 
                                      "format='" * format * "'"    
  return (String(take!(io)), spec)
end

struct GPDataImage <: GPAbstractDataFile
  file::String
  source::String

  function GPDataImage(args...; option="")
    data, spec = to_imagedata(args...; option=option)
    (file, io) = mktemp()
    write(io, data)
    close(io)
    return new(file, " '$file' volatile $spec ")
  end

  function GPDataImage(v::T, fn1::Function, fns::Vararg{Function, N}; option="") where {T <: AbstractVector, N}
    args = (fn1, fns...)
    args = map((f)->(f.(v)), args)
    return GPDataImage(v, args...; option=option)
  end

  function GPDataImage(v1::T, v2::T, fn1::Function, fns::Vararg{Function, N}; option="") where {T <: AbstractVector, N}
    args = (fn1, fns...)
    args = map((f)->(f.(v1',v2)), args)
    return GPDataImage(v1, v2, args...; option=option)
  end

end

Base.print(io::IO, obj::GPDataImage) = Base.print(io, obj.source)

function to_meshdata(v1::T, v2::T, args::Vararg{AbstractMatrix, N}; option="") where {T <: AbstractMatrix, N}
  dims1 = size(v1)
  if size(v2) != dims1
    error("dimension mismatch in given vectors")
  end
  if any([size(args[k]) != dims1.-1 for k=1:N])
    error("dimension mismatch in given vectors")
  end
  dims = dims1.-1
  io = IOBuffer()
  v1 = Float32.(v1)
  v2 = Float32.(v2)
  nans = [NaN32 for k=1:N]
  count = 0
  for i=1:dims[2], j=1:dims[1]
    values = [to_float32(args[k][j,i]) for k=1:N]
    write(io, v1[j,i], v2[j,i]);     write(io, values...)
    write(io, v1[j,i+1], v2[j,i+1]);   write(io, values...)
    write(io, v1[j+1,i+1], v2[j+1,i+1]); write(io, values...)
    write(io, v1[j+1,i], v2[j+1,i]);   write(io, values...)
    write(io, v1[j,i], v2[j,i]);     write(io, values...)
    write(io, NaN32, NaN32);         write(io, nans...)
    count += 6
  end
  spec = "binary record=$count $option format='" * "%float32"^(N+2) * "'"    
  return (String(take!(io)), spec)
end

function to_meshdata(v1::T, v2::T, args::Vararg{AbstractMatrix, N}; option="") where {T <: AbstractVector, N}
  dims1 = (length(v2), length(v1)) 
  if any([size(args[k]) != dims1.-1 for k=1:N])
    error("dimension mismatch in given vectors")
  end
  dims = dims1.-1
  v1 = Float32.(v1)
  v2 = Float32.(v2)
  io = IOBuffer()
  nans = [NaN32 for k=1:N]
  count = 0
  for i=1:dims[2], j=1:dims[1]
    values = [to_float32(args[k][j,i]) for k=1:N]
    write(io, v1[i], v2[j]);     write(io, values...)
    write(io, v1[i+1], v2[j]);   write(io, values...)
    write(io, v1[i+1], v2[j+1]); write(io, values...)
    write(io, v1[i], v2[j+1]);   write(io, values...)
    write(io, v1[i], v2[j]);     write(io, values...)
    write(io, NaN32, NaN32);     write(io, nans...)
    count += 6
  end
  spec = "binary record=$count $option format='" * "%float32"^(N+2) * "'"    
  return (String(take!(io)), spec)
end

struct GPDataMesh <: GPAbstractDataFile
  file::String
  source::String

  function GPDataMesh(args...; option="")
    data, spec = to_meshdata(args...; option=option)
    (file, io) = mktemp()
    write(io, data)
    close(io)
    return new(file, " '$file' volatile $spec ")
  end

end

Base.print(io::IO, obj::GPDataMesh) = Base.print(io, obj.source)

function to_mesh3d(v1::T, v2::T, v3::T, args::Vararg{AbstractMatrix, N}; option="") where {T <: AbstractMatrix, N}
  dims1 = size(v1)
  if size(v2) != dims1 || size(v3) != dims1
    error("dimension mismatch in given vectors")
  end
  if any([size(args[k]) != dims1.-1 for k=1:N])
    error("dimension mismatch in given vectors")
  end
  dims = dims1.-1
  io = IOBuffer()
  v1 = Float32.(v1)
  v2 = Float32.(v2)
  v3 = Float32.(v3)
  count = 0
  for i=1:dims[2], j=1:dims[1]
    values = [args[k][j,i] for k=1:N]
    write(io, v1[j,  i],   v2[j,  i],   v3[j,  i]);   write(io, values...)
    write(io, v1[j,  i+1], v2[j,  i+1], v3[j,  i+1]); write(io, values...)
    write(io, v1[j+1,i+1], v2[j+1,i+1], v3[j+1,i+1]); write(io, values...)
    write(io, v1[j+1,i],   v2[j+1,i],   v3[j+1,i]);   write(io, values...)
    write(io, v1[j,  i],   v2[j,  i],   v3[j,  i]);   write(io, values...)
    write(io, NaN32,       NaN32,       NaN32);       write(io, values...)
    count += 6
  end
  format = "%float32%float32%float32" * join([eltype2format(args[k]) for k=1:N],"")
  spec = "binary record=$count $option format='" * format * "'"    
  return (String(take!(io)), spec)
end

function to_mesh3d_text(v1::T, v2::T, v3::T, args::Vararg{AbstractMatrix, N}; option="") where {T <: AbstractMatrix, N}
  dims1 = size(v1)
  if size(v2) != dims1 || size(v3) != dims1
    error("dimension mismatch in given vectors")
  end
  if any([size(args[k]) != dims1.-1 for k=1:N])
    error("dimension mismatch in given vectors")
  end
  dims = dims1.-1
  io = IOBuffer()
  count = 0
  for i=1:dims[2], j=1:dims[1]
    values = [obj2text(args[k][j,i]) for k=1:N]
    print(io, join((obj2text(v1[j,i]), obj2text(v2[j,i]), obj2text(v3[j,i]), values...), " "), "\n")
    print(io, join((obj2text(v1[j,i+1]), obj2text(v2[j,i+1]), obj2text(v3[j,i+1]), values...), " "), "\n")
    print(io, join((obj2text(v1[j+1,i+1]), obj2text(v2[j+1,i+1]), obj2text(v3[j+1,i+1]), values...), " "), "\n")
    print(io, join((obj2text(v1[j+1,i]), obj2text(v2[j+1,i]), obj2text(v3[j+1,i]), values...), " "), "\n")
    print(io, join((obj2text(v1[j,i]), obj2text(v2[j,i]), obj2text(v3[j,i]), values...), " "), "\n")
    print(io, "\n")
  end
  return (String(take!(io)), option)
end

struct GPDataMesh3D <: GPAbstractDataFile
  file::String
  source::String

  function GPDataMesh3D(args...; option="", format="binary")
    @show format
    if format == "text"
      data, spec = to_mesh3d_text(args...; option=option)
    else
      data, spec = to_mesh3d(args...; option=option)      
    end
    (file, io) = mktemp()
    write(io, data)
    close(io)
    return new(file, " '$file' volatile $spec ")
  end

end

Base.print(io::IO, obj::GPDataMesh3D) = Base.print(io, obj.source)

function argsconv(args...)
  if ! any(x->isa(x,Real),args)
    return args
  end
  maxndims = maximum(map(x->ndims(x), args))
  if maxndims == 0
    return map(x->[x], args)
  end
  dims = size(argmax(x->length(x), args))
  list = []
  for arg in args
    if isa(arg, Real)
      push!(list, repeat([arg],inner=dims))
    else
      push!(list, arg)
    end
  end
  return list
end

function array(arg::AbstractArray)
  put("print 'setting data'")
  return GPDataArray(arg)
end

function inline(args...; option="")
  put("print 'setting data'")
  return GPDataBlock(argsconv(args...)...; option=option)
end

function text(args...; option="")
  put("print 'setting data'")
  return GPDataFile(argsconv(args...)...; option=option)
end

function binary(args...; option="")
  put("print 'setting data'")
  return GPDataBinary(argsconv(args...)...; option=option)
end

function image(args...; option="")
  put("print 'setting data'")
  return GPDataImage(argsconv(args...)...; option=option)
end

function mesh(args...; option="")
  put("print 'setting data'")
  return GPDataMesh(argsconv(args...)...; option=option)
end

function mesh3d(args...; option="", format="binary")
  put("print 'setting data'")
  return GPDataMesh3D(argsconv(args...)...; option=option, format=format)
end

function file(filename::String)
  put("print 'setting data'")
  return "\"" * filename * "\""
end

#
# undefine
#
function undefine(obj::GPDataBlock)
  put("undefine $obj")
end

function undefine(obj::GPAbstractDataFile)
  if isfile(obj.file)
    rm(obj.file, force=true)
  end
end

function undefine(args...)
  for obj in args
    undefine(obj)
  end
end