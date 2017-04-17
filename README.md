# DeduplicateFiles.jl

[![Build Status](https://travis-ci.org/perrutquist/DeduplicateFiles.jl.svg?branch=master)](https://travis-ci.org/perrutquist/DeduplicateFiles.jl) [![Coverage Status](https://coveralls.io/repos/perrutquist/DeduplicateFiles.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/perrutquist/DeduplicateFiles.jl?branch=master)

** This software deletes files. If it is used incorrectly, or if it has bugs,
it may delete the wrong ones, causing data loss and/or rendering your system
unusable. Make sure you have backed up all your data before proceeding. **

This julia module helps with finding and deleting duplicate files. There are
already numerous pieces of software, both free and commercial, that do this.
Most of them have nice-looking graphical user interfaces. This module does not
have a graphical user interface, or even a command-line interface. It can only
be used from within julia.

Instead of answering questions about which files to delete (which can be a very
time-consuming process when there are lots of files to de-duplicate) the user
writes a function that tells the software when one of two identical files should
be deleted.

## Example

Let's assume that we want to find all duplicate files under the directory `foo`,
and for each set of duplicates, keep one file. (We don't care which one.)

We're not allowed to use a decision function that simply returns `true` for any
pair of files. It is required to be consistent in its choice of files to
delete. So we use alphabetical ordering of the file paths as a tie breaker.

```
list = deduplicate_files("foo", (a,b)->A.realpath > B.realpath, verbose=true, dry_run=true)
```

We then examine the returned list. If all looks good, we re-run the command
without the `dry_run` argument.

## Usage

The typical way to use the software is to first call the function
`list = deduplicate_files(startdirs, dfun, dry_run=true)`, where `startdirs`
is an array of directory paths, and `dfun` is a "decision function" that tells
the software which file(s) to delete from a set up duplicates. The directories
will be searched recursively and the duplicate files that would be deleted will
be stored in a list. If the list looks correct, then the function can be called
again, without `dry_run=true` causing the files to actually be deleted.
Otherwise, the decision function must be re-written, and a new dry run performed.

The decision function `dfun(A,B)` must satisfy the following criteria:
 * It takes as input arguments two `DeduplicationFile` structs.
 * It should return `true` if the file that `A` points to should be deleted
   after confirming that it is identical to the one that `B` points to.
   (And `false` otherwise.)
 * It must behave like an `isless` function, establishing a consistent order.
   For example, `dfun(x,y)` and `dfun(y,x)` may not both be `true`. (But they
   may both be `false` if neither `x` nor `y` should be deleted.)
 * It must not assume that the given files are identical. The software is
   allowed to call the decision function on suspected duplicates, deferring the
   byte-for-byte comparison until just before a duplicate is deleted.
 * It should NOT delete the duplicate file. (This can have disastrous
   consequences if the user only intended to do a dry run.)

The `DeduplicationFile` descriptors provided in the arguments to the decision
function have the following fields:
 * `start` - The starting point given.
 * `realstart` - The absolute path of `start`, after expanding symbolic links.
 * `relpath` - The relative path from `start` to the file in question.
 * `realpath` - The absolute path to the file, after expanding symbolic links.
 * `dirname` - The directory part of `realpath`.
 * `dirinode` - The inode number of the directory in which the file resides.
 * `basename` - The filename.
 * `stat` - The `StatStruct` for the file. (See the documentation for `stat`.)

## Another example

Let's assume that `foo` and `bar` are directories.
We want to delete files under `foo` that have identical copies somewhere under
`bar`, but only if they are larger than one kilobyte, the filenames are
identical, and they are not hard-linked to the same inode. (Deleting hard-linked
copies doesn't free up much disk space, so we keep them.)

We write a decision function for this:
```
const p1 = "/path/to/foo"
const p2 = "/path/to/bar"
dfun(a,b) = a.start == p1 && b.start == p2 &&
            a.stat.size > 1024 && a.basename == b.basename &&
            a.stat.inode != b.stat.inode
```

Then we test our decision function by doing a dry run.
```
list = deduplicate_files([p1, p2], dfun, dry_run=true)
```

We might store the returned list to disk in order to keep a record of the
files that were deleted and where their identical copies were found.

## Note

** This software is provided as-is, without any warranty of any kind. **

I wrote it in my spare time, because I needed it myself, and I open-sourced it
in case somebody else might find it useful.

I haven't done any extensive testing, other than using it for the specific task
that I wrote it for. In particular, I've never tested this on a file-system with
hard-linked directories. (Why would you use hard-linked directories?)

If using this software breaks your system, I will not be able to help you in
any way, except to tell you to restore from backups. You did make backups,
didn't you?
