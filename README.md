
# Table of Contents

1.  [Description](#orgb2018a9)
2.  [Prerequisites](#org1b18661)
3.  [Quick start](#org751ec71)
    1.  [Initial setup](#org2924cf8)
    2.  [Uploading and downloading files](#org2e8e68e)
4.  [Commands](#org750da8e)
5.  [Source code files](#org11f6018)
6.  [Limitations](#org1526aee)
7.  [License](#orga6e9cff)

Intended for linux users who have [emacs](https://www.gnu.org/software/emacs/) always open.


<a id="orgb2018a9"></a>

# Description

Synchronizing important files on two or more computers using

1.  `emacs` + GNU `make`,
2.  some sort of a cloud that can be mounted to a directory, for example, an
    a. ssh-server, or
    b. some public cloud service (e.g., Russian [Yandex Disk](https://disk.yandex.com/) or Swiss [pCloud](https://www.pcloud.com)) that can be mounted in linux
       using standard open-source utilities,
    and
3.  symmetric encryption
    a. using [ImageMagick](https://imagemagick.org/) for `JPEG` and `PNG` images or
    b. using [gpg](https://www.gnupg.org/) for other (presumably text) files.

Encrypted files saved in the cloud have **random names** to minimize the amount of information cloud owners can extract by monitoring our cloud directory.


<a id="org1b18661"></a>

# Prerequisites

We need

1.  `emacs`, GNU `make`, `ImageMagick`, `gpg`, `sed`, and `gawk`; in Debian these can be installed as follows:  
    `aptitude install emacs make imagemagick gpg sed gawk`
2.  [lisp-goodies](https://github.com/chalaev/lisp-goodies): [batch-start.el](https://github.com/chalaev/lisp-goodies/blob/master/packaged/batch-start.el) (used by [Makefile](Makefile)), and [shalaev.el](https://github.com/chalaev/lisp-goodies/blob/master/packaged/shalaev.el)


<a id="org751ec71"></a>

# Quick start

I am running `emacs` in daemon mode (in text console) using the following line in [~/.login](https://github.com/chalaev/lisp-goodies/blob/master/.login):

    emacs --daemon

Once `emacs` was started in the daemon mode, I can use `emacsclient -c` to open a new (gui) emacs window.


<a id="org2924cf8"></a>

## Initial setup

1.  `mkdir ~/.emacs.d/local-packages/`
2.  Place [shalaev.el](https://github.com/chalaev/lisp-goodies/blob/master/packaged/shalaev.el) and [cloud.el](packaged/cloud.el) to `~/.emacs.d/local-packages/`
3.  Load [batch-start.el](goodies/batch-start.el) in your [~/.emacs](.emacs)
4.  Evaluate `cloud.el` in `emacs` at start by placing the following lines
    
        (require 'cloud)
        (cloud-start)
    
    into your [~/.emacs](.emacs) file. Update some files in emacs, then `M-x cloud-sync`.
    During the very first `(cloud-start)` run, configuration file [~/.emacs.d/cloud/\`hostname\`/config](config) will be created.
5.  Mount remote directory. The mounting point may be arbitrary (specified as `cloud-directory` in [~/.emacs.d/cloud/\`hostname\`/config](config)), the default one is `/mnt/cloud/`.


<a id="org2e8e68e"></a>

## Uploading and downloading files

There are several log files; the least informative one is ``~/.emacs.d/cloud/`hostname`/log`` described in [files.org](files.org).

1.  Edit a text file in emacs. Unless it is blacklisted it will automatically be clouded when you save it. (Blacklisted files can be manually clouded using `M-x cloud-add`.)
2.  Run `M-x cloud-sync` to upload the file and ``tail -f ~/.emacs.d/cloud/`hostname`/log`` to see the log.
3.  Now you can move to another host (e.g. from your office desktop to your laptop).
4.  Using some secure way, copy [~/.emacs.d/cloud/\`hostname\`/config](config) to another host; launch `cloud.el` there and check the log files.
    Ensure that updated on your previous host files were downloaded to your current host.
5.  [Let me know](https://github.com/chalaev/cloud/issues/new/choose) if something is unclear or does not work.

Every time we `M-x cloud-sync`, local files get synchronized with the cloud.
(The same happens when we start/quit emacs.)
For this purpose I have a line in my `crontab`:  
`43 9-21 * * * emacsclient -e "(cloud-sync)" &> /dev/null`


<a id="org750da8e"></a>

# Commands

Except for `M-x cloud-sync`, commands are barely used:

-   `M-x cloud-add` adds one or several files to the list of "clouded" files.
    This means that `M-x cloud-sync` command will upload these "clouded" files to the remote server if they are updated. Supposed to be used in dired buffer for several
    (marked) files, or (when no files are marked) for a single file. **Files edited in emacs are clouded automatically,** but there are exceptions – see the
    [sample configuration file](config) and the [source code](cloud.org).
    Works both on files and directories.
-   `M-x cloud-forget` is the opposite of `M-x cloud-add`. 
    It is also called automatically when files are removed in dired buffer. Currently works on files only, not on directories.
-   `M-x cloud-sync` syncronizes local files with the cloud. Could be regularly called with a `crontab` line, e.g.,  
    `43 9-21 * * * emacsclient -e "(cloud-sync)" &> /dev/null`


<a id="org11f6018"></a>

# Source code files

(Dynamically created/updated logs and data files are described in [files.org](files.org).)

1.  [README.org](README.org) generates `README.md` for [notabug](https://notabug.org/shalaev/emacs-cloud) and [github](https://github.com/chalaev/cloud).
2.  [cloud.org](cloud.org) contains the code from [generated/main.el](generated/main.el) together with explanations.
3.  [0.el](0.el), [1.el](1.el), and [2.org](2.org) are kind of "Appendix" containing some pieces of code which not interesting enough to be included in [cloud.org](cloud.org).
4.  [Makefile](Makefile) merges all the code into [packaged/cloud.el](packaged/cloud.el) which is the main file to be launched when `emacs` starts.
5.  [shell/cloud-git](shell/cloud-git) synchronizes file operations in `git` with this code, for example:  
    `cloud-git rm files.org` or `cloud-git mv log-files.org files.org`
6.  [testing.org](testing.org) describes multi-scale testing procedure.
7.  [bugs.org](bugs.org) contains
    a. error and problem list, and
    b. ideas on further development.


<a id="org1526aee"></a>

# Limitations

1.  I use [GNU make](https://www.gnu.org/software/make/) together with its `--jobs` option to enjoy [(unsupported in emacs)](https://www.emacswiki.org/emacs/EmacsLispLimitations) multi-threading, and thus
    I have to suffer from the [make](https://www.gnu.org/software/make/) restriction: only nicely named files will work.  
    In particular, **no spaces in file names** are allowed.
    (This limitation can probably be circumvented by creating soft links to badly named files.)
2.  Encrypting images is just a toy feature for now; it has to be better developed to become really useful.
    After encrypting an image file and then decrypting it back, we get the same, but not identical picture (file size is changed).


<a id="orga6e9cff"></a>

# License

This code is released under [MIT license](https://mit-license.org/).

