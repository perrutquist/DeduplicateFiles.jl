module DeduplicateFiles

using CRC

export DeduplicationFile, same_file, identical_files,
       delete_duplicate_file, indexfiles, deduplicate_files

"A structure with data about files to keep/delete."
struct DeduplicationFile
  start::String
  realstart::String
  relpath::String
  realpath::String
  dirname::String
  dirinode::UInt64
  basename::String
  stat::Base.Filesystem.StatStruct
end

"A hash that is unique for the file"
file_id(x::DeduplicationFile) = hash(x.basename, hash(x.dirinode, hash(x.stat.device)))

"Determine if two paths are hard-linked to the same inode"
function is_hardlink(a,b)
  sa = stat(a)
  sb = stat(b)
  return sa.device == sb.device && sa.inode == sb.inode
end
is_hardlink(a::DeduplicationFile,b::DeduplicationFile) =
  a.stat.device == b.stat.device && a.stat.inode == b.stat.inode

"""
Determine if two paths point to the same directory entry.

This function returns `true` iff `a` and `b` both refer to the same directory
entry. This can happen if directories on either path are symbolic or hard
links to directories on the other path.

If `a` and `b` point to the same directory entry, then deleting `a` will also
delete `b`, so it would be bad to mistake `b` for a backup copy of `a`.

If `a` and/or `b` are symbolic links, then this function checks whether the
*links* are stored in the same directory entry. It does *not* check if they
point to the same or different files.

NOTE: This has *never been tested* on a file-system with hard-linked
directories. (Why would you use hard-linked directories?)
"""
function same_file(a::AbstractString, b::AbstractString)
  basename(a) == basename(b) || return false
  dira = dirname(abspath(a))
  dirb = dirname(abspath(b))
  realpath(dira) != realpath(dirb) || return true
  sa = stat(dira)
  sb = stat(dirb)
  return sa.device == sb.device && sa.inode == sb.inode
end

"Determine if two files are byte-for-byte identical"
function identical_files(a::IO, b::IO; buflen::Int=1048576)
  stat(a).size == stat(b).size || return false
  # TODO: Option to pass buffers as arguments and avoid repeated allocation.
  buf_a = Array{UInt8}(undef, buflen)
  buf_b = Array{UInt8}(undef, buflen)
  while (n_a = readbytes!(a, buf_a)) > 0
    n_b = readbytes!(b, buf_b)
    n_a == n_b || return false
    view(buf_a, 1:n_a) == view(buf_b, 1:n_b) || return false
  end
  return true
end
function identical_files(a::AbstractString, b::AbstractString; kwargs...)
  !same_file(a,b) || throw(ArgumentError("Cannot compare a file to itself."))
  result = false
  open(a, "r") do af
    open(b, "r") do bf
      result = identical_files(af, bf; kwargs...)
    end
  end
  return result
end

"""
   `delete_duplicate_file(; delete=file_to_delete, keep=file_to_keep)`

Delete a file if, and only if, it is an identical copy of another file.

The files to delete and keep are compared byte-for-byte. If they are
identical, then `file_to_delete` is deleted, and the function returns `true`.

If the files differ, or if both file paths refer to the same file (e.g. via
symbolic links) then no file is removed, and the function returns `false`.

The `file_to_delete` may not be a symbolic link. (The `file_to_keep` may be a
symbolic link, but if it points to the `file_to_delete`, then, obviously, that
file will not be deleted.)

This function cannot be called as `delete_duplicate_file("file1", "file2")`
because there might be confusion as to which file should be kept.

`delete_duplicate(..., dry_run=true)` does not delete files, but only returns
`true` or `false` depending on if a file would have been deleted.

`delete_duplicate(..., replace_with=:symlink)` replaces the deleted file with
a symbolic link to the `file_to_keep`.

`delete_duplicate(..., replace_with=:hardlink)` replaces the deleted file with
a hard link. If the files are not on the same file system, then an error is
thrown and no file is deleted. (Requires `ln` to be available via system call.)

`delete_duplicate(..., delete_hardlinks=true)` deletes the `file-to-delete`
even if it is a hardlink to `file-to-keep` (and therefore didn't occupy any
extra disk space).
"""
function delete_duplicate_file(; delete::AbstractString="", keep::AbstractString="",
                               dry_run::Bool=false, replace_with::Symbol=:nothing,
                               delete_hardlinks::Bool=false, verbose::Bool=false)
  (!isempty(delete) && !isempty(keep)) || throw(ArgumentError("Missing file name."))
  !islink(delete) || error("The file to delete must not be as symbolic link.")
  replace_with in [:nothing, :symlink, :hardlink] ||
      throw(ArgumentError("Illegal value for replace_with: ", string(replace_with)))

  # Follow symlinks now, so that we're not caught by a symlink that changes
  # between comparing the files and deleting.
  delete = realpath(delete)
  keep = realpath(keep)

  replace_with != :hardlink || stat(delete).device == stat(keep).device ||
      error("Cannot create hard-links across file systems.")

  !same_file(delete, keep) || return false

  hl = is_hardlink(delete, keep)

  hl || identical_files(delete, keep) || return false

  verbose && println(dry_run ? "Would delete " : "Deleting ", delete, " as duplicate of ", keep, " (", stat(delete).size, " byters)")

  if !dry_run && (!hl || ( hl && delete_hardlinks && replace_with != :hardlink ))
    rm(delete)
    if replace_with == :symlink
      symlink(keep, delete)
    elseif replace_with == :hardlink
      run(`ln $keep $delete`)
    end
  end

  # If deleting the `delete` file somehow removed the `keep` file,
  # then there's a serious problem. Stop immediately!
  # (This should never happen.)
  isfile(keep) || error("Deleting ", delete, " somehow removed ", keep)

  return true
end

"""
   `indexfiles(start; idx, follow_symlinks=false)`

Create an index of all files found when walking the directory tree.
Returns an iterator over `DeduplicationFile` objects.
"""
function indexfiles(start::AbstractString; idx=Dict{UInt64,DeduplicationFile}(),
      follow_symlinks=false)
  realstart = realpath(start)
  for (root, dirs, files) in walkdir(realstart, follow_symlinks=follow_symlinks)
    ds = stat(root)
    for file in files
      ff = joinpath(root, file)
      if !islink(ff)
        df = DeduplicationFile(start, realstart, relpath(ff, realstart),
            realpath(ff), dirname(realpath(ff)), ds.inode, file, stat(ff))
        idx[file_id(df)] = df
      end
    end
  end
  return values(idx)
end

function indexfiles(starts::AbstractArray; idx=Dict{UInt64,DeduplicationFile}(),
    follow_symlinks=false)
  for start in starts
    indexfiles(start, idx=idx, follow_symlinks=follow_symlinks)
  end
  return values(idx)
end

"""
   `processdups(by, proc, list)`

Apply the `by` function to each item in `list`, for every set of two or more
items that generated identical `by` values, call `proc` on that set.
The `proc` function should return a list, and processdups returns a
concatenation of all returned lists.
"""
function processdups(by::Function, proc::Function, list::AbstractArray; quickpair::Bool=false)
  if quickpair && length(list)==2
    return(proc(list))
  end

  ret = Array{Any,1}[]

  length(list) >= 2 || return ret

  bylist = map(i->(i, by(list[i])), 1:length(list));

  # First sort the list...
  sort!(bylist, by=i->i[2])

  # ...then go through the list. Duplicates will be next to each other.
  ci = 1;
  cmp = bylist[ci][2]
  for i=1:length(bylist)
    if i==length(bylist) || bylist[i+1][2] != cmp
      if i>ci
        sublist = map(j->list[bylist[j][1]], ci:i)
        ret = vcat(ret, proc(sublist))
      end
      ci = i+1;
      if i<length(bylist)
        cmp = bylist[ci][2];
      end
    end
  end
  return ret
end

"""
   `deldups(list, dfun; dry_run)`

Determine which files from a list of suspected duplicates that should be
deleted according to the decision function `dfun`, and delete them if they
actually are duplicates.
"""
function deldups(list, dfun; kwargs...)
  deleted = Array{Tuple{DeduplicationFile, DeduplicationFile}, 1}();
  sort!(list, lt=dfun)
  lmax = length(list)
  i = 1
  while i<lmax
    for j=length(list):-1:i+1
      if dfun(list[i], list[j]) && delete_duplicate_file(delete=list[i].realpath,
             keep=list[j].realpath; kwargs...)
        push!(deleted, (list[i], list[j]))
        lmax = j
        break
      end
    end
    i = i+1
  end
  return deleted
end

const crc32 = crc(CRC_32)

"Run crc32 on the first `buflen` bytes of a file"
function partialcrc32(a::IO; buflen::Int=1048576)
  buf_a = Array{UInt8}(buflen)
  n_a = readbytes!(a, buf_a)
  if n_a != length(buf_a)
    buf_a = buf_a[1:n_a]
  end
  return crc32(buf_a)
end

"Divide list by crc, and run deldups on each sub-list"
crcdeldups(list, dfun; kwargs...) =
  processdups(x->open(crc32, x.realpath), lst->deldups(lst, dfun; kwargs...), list, quickpair=true)

"Divide list by partial crc, and run crcdeldups on each sub-list"
pcrcdeldups(list, dfun; kwargs...) =
  processdups(x->open(partialcrc32, x.realpath), lst->crcdeldups(lst, dfun; kwargs...), list)

"Divide list by size, then run pcrcdeldups/crcdeldups on each sub-sub-list"
sizcrcdeldups(list, dfun; kwargs...) =
  processdups(x->x.stat.size, lst -> lst[1].stat.size>1048576 ? pcrcdeldups(lst, dfun; kwargs...) : crcdeldups(lst, dfun; kwargs...), list)

"""
   `list = deduplicate_files(startdirs, dfun)`

Scan `startdirs` recursively for files, call dfun on pairs of suspected
duplicates, and delete identical copies when dfun returns true.
"""
function deduplicate_files(startdirs, dfun; verbose::Bool=false, kwargs...)
  list = indexfiles(startdirs)
  if verbose
    println("Indexed ", length(list), " files.")
  end
   sizcrcdeldups(collect(list), dfun; verbose=verbose, kwargs...)
end

# Define a `show` method for tuples of deduplication files, to make it easier to
# read the returned array from `deduplicate_files`.
import Base.show
show(io::IO, t::Tuple{DeduplicationFile, DeduplicationFile}) = print(io,
  joinpath(t[1].start, t[1].relpath), " duplicate of ", joinpath(t[2].start, t[2].relpath))

"The total size (in bytes) of an array of `DeduplicationFile`s"
totalsize(x::DeduplicationFile) = x.stat.size
totalsize(x::Tuple{DeduplicationFile, DeduplicationFile}) = totalsize(x[1])
totalsize(x::AbstractArray) = sum(totalsize.(x))

# TODO: Check with dfun that at least one duplicate might be deleted
#       before doing CRC.

end # module
