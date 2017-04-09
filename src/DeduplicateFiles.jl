module DeduplicateFiles

export DeduplicationFile, same_file, identical_files,
       delete_duplicate_file, indexfiles

"A structure with data about files to keep/delete."
type DeduplicationFile
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
  buf_a = Array{UInt8}(buflen)
  buf_b = Array{UInt8}(buflen)
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
                               dry_run=false, replace_with=:nothing, delete_hardlinks=false)
  (!isempty(delete) && !isempty(keep)) || throw(ArgumentError("Missing file name."))
  !islink(delete) || error("The file to delete must not be as symbolic link.")
  replace_with in [:nothing, :symlink, :hardlink] ||
      throw(ArgumentError("Illegal value for replace_with: ", string(replace_with)))

  # Follow symlinks now, so that we're not caught by a symlink that changes
  # between comparing the files and deleting.
  delete = realpath(delete)
  keep = realpath(keep)

  replace_with != :hardlink || stat(a).device == stat(b).device ||
      error("Cannot create hard-links across file systems.")

  !same_file(delete, keep) || return false

  hl = is_hardlink(delete, keep)

  hl || identical_files(delete, keep) || return false

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

end # module
