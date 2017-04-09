using DeduplicateFiles
using Base.Test

# A temporary directory to do tests in
const testdir = mktempdir();

# Some filepaths to use in tests
const testpaths = joinpath.([testdir],["dir1" "dir2"],
    ["file1", "file2", "file3", "file4", "file5", "file6", "file7", "file8"])

# Utility function that creates a file containing a string.
function strfile(str, pth)
  open(pth,"w") do f
    write(f,str)
  end
end

try
  # Generate a few directories, files and symlinks to test deduplication on
  mkdir(dirname(testpaths[1,1]))
  mkdir(dirname(testpaths[1,2]))
  strfile("dup 1", testpaths[1])
  strfile("dup 1", testpaths[2])
  strfile("dup 1", testpaths[3])
  strfile("nodup", testpaths[4])
  strfile("dup two", testpaths[5])
  strfile("dup two", testpaths[6])
  strfile("unique", testpaths[7])
  strfile("unique2", testpaths[8])
  strfile("MAHAVFT (CRC32 collision)", testpaths[9])
  strfile("VJM (CRC32 collision)", testpaths[10])
  strfile("KSETVMW (CRC32 collision 2)", testpaths[11])
  strfile("XNGMFOX (CRC32 collision 2)", testpaths[12])
  symlink("file2", testpaths[13])
  symlink("file2", testpaths[14])
  symlink("file5", testpaths[15])

  # tests
  @test(same_file(testpaths[1], testpaths[1]) === true)
  @test(same_file(testpaths[1], testpaths[2]) === false)
  @test(same_file(testpaths[1], testpaths[3]) === false)

  @test(identical_files(testpaths[1], testpaths[2]) === true)
  @test(identical_files(testpaths[1], testpaths[4]) === false)
  @test(identical_files(testpaths[1], testpaths[2], buflen=1) === true)
  @test(identical_files(testpaths[1], testpaths[4], buflen=1) === false)
  @test(identical_files(testpaths[7], testpaths[8], buflen=1) === false)

  @test(delete_duplicate_file(delete=testpaths[1], keep=testpaths[2]) === true)
  @test(!isfile(testpaths[1]))
  strfile("dup 1", testpaths[1]) # re-create deleted file

  @test(delete_duplicate_file(delete=testpaths[1], keep=testpaths[4]) === false)
  @test(isfile(testpaths[1]))

  @test(!islink(testpaths[1]))
  @test(islink(testpaths[15]))
  @test(length(indexfiles(testdir))==12)

  # TODO: Try using "mount -t bind" and/or creating hard-linked directories
  #       producing different paths to the same file.

finally
  rm(testdir, force=true, recursive=true)
end
