using DeduplicateFiles
using Base.Test

# A temporary directory to do tests in
const testdir = mktempdir();

# Some filepaths to use in tests
const testpaths = joinpath.([testdir],["dir1" "dir2"],
    ["file1", "file2", "file3", "file4", "file5", "file6", "file7", "file8"])

const dir1 = dirname(testpaths[1,1]);
const dir2 = dirname(testpaths[1,2]);

# Utility function that creates a file containing a string.
function strfile(str, pth)
  open(pth,"w") do f
    write(f,str)
  end
end

function testproc(list)
  return [list]
end

try
  # Generate a few directories, files and symlinks to test deduplication on
  mkdir(dir1)
  mkdir(dir2)
  strfile(b"dup 1", testpaths[1,1])
  strfile(b"dup 1", testpaths[1,2])
  strfile(b"dup 1", testpaths[2,1])
  strfile(b"nodup", testpaths[2,2])
  strfile(b"dup two", testpaths[3,1])
  strfile(b"dup two", testpaths[3,2])
  strfile(b"unique", testpaths[4,1])
  strfile(b"unique2", testpaths[4,2])
  strfile(b"MAHAVFT (CRC32 collision)", testpaths[5,1])
  strfile(b"VJM (CRC32 collision)", testpaths[5,2])
  strfile(b"KSETVMW (CRC32 collision 2)", testpaths[6,1])
  strfile(b"XNGMFOX (CRC32 collision 2)", testpaths[6,2])
  symlink(testpaths[1,2], testpaths[7,1])
  symlink(testpaths[1,2], testpaths[7,2])
  symlink(testpaths[6,2], testpaths[8,1])
  symlink(dirname(testpaths[1,1]), testpaths[8,2])

  @assert(!islink(testpaths[1,1]))
  @assert(islink(testpaths[7,1]))

  #run(`ls -lR $testdir`) # list the test files and links that were just created.

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

  filelist = collect(indexfiles(testdir))
  @test(length(filelist)==12)
  @test(length(indexfiles(testdir,follow_symlinks=true))==12)

  procresult = DeduplicateFiles.processdups(x->x.stat.size, testproc, filelist)
  #show(procresult)

  @test(length(deduplicate_files([dir1, dir2], (x,y)->(x.start==dir1 && y.start==dir2), dry_run=true, verbose=true))==3)
  @test(isfile(testpaths[1,1]) && isfile(testpaths[1,2]) &&
        isfile(testpaths[2,1]) && isfile(testpaths[2,2]) &&
        isfile(testpaths[3,1]) && isfile(testpaths[3,2]) &&
        isfile(testpaths[4,1]) && isfile(testpaths[4,2]) &&
        isfile(testpaths[5,1]) && isfile(testpaths[5,2]) &&
        isfile(testpaths[6,1]) && isfile(testpaths[6,2]) )

  @test(length(deduplicate_files([dir1, dir2], (x,y)->(x.start==dir1 && y.start==dir2)))==3)
  @test(!isfile(testpaths[1,1]) && isfile(testpaths[1,2]) &&
        !isfile(testpaths[2,1]) && isfile(testpaths[2,2]) &&
        !isfile(testpaths[3,1]) && isfile(testpaths[3,2]) &&
        isfile(testpaths[4,1]) && isfile(testpaths[4,2]) &&
        isfile(testpaths[5,1]) && isfile(testpaths[5,2]) &&
        isfile(testpaths[6,1]) && isfile(testpaths[6,2]) )

  @test(length(deduplicate_files([dir1, dir2], (x,y)->(x.start==dir2 && y.start==dir1)))==0)
  strfile("dup 1", testpaths[1,1])
  strfile("dup 1", testpaths[2,1])
  strfile("dup two", testpaths[3,1])

  lst = deduplicate_files([dir1, dir2], (x,y)->(x.start==dir2 && y.start==dir1))
  @test(length(lst)==2)
  @test(DeduplicateFiles.totalsize(lst)==5+7)
  @test(isfile(testpaths[1,1]) && !isfile(testpaths[1,2]) &&
        isfile(testpaths[2,1]) && isfile(testpaths[2,2]) &&
        isfile(testpaths[3,1]) && !isfile(testpaths[3,2]) &&
        isfile(testpaths[4,1]) && isfile(testpaths[4,2]) &&
        isfile(testpaths[5,1]) && isfile(testpaths[5,2]) &&
        isfile(testpaths[6,1]) && isfile(testpaths[6,2]) )
  strfile("dup 1", testpaths[1,2])
  strfile("dup two", testpaths[3,2])


  # TODO: Try using "mount -t bind" and/or creating hard-linked directories
  #       producing different paths to the same file.

finally
  rm(testdir, force=true, recursive=true)
end
