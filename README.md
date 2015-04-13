# openbsd-builder

A project that builds an OpenBSD release of -stable for local site-wide use.

The original goal for this project was an automated means by which a user or organization could build an OpenBSD release, updated to the -stable branch containing all post-release patches. Think of it as an automated version of sections [5.3](http://www.openbsd.org/faq/faq5.html#Bld), [5.4](http://www.openbsd.org/faq/faq5.html#Bld), and [5.5](http://www.openbsd.org/faq/faq5.html#Xbld) of OpenBSD's [FAQ](http://www.openbsd.org/faq/).

This project uses a Vagrant VM under the hood and performs at least one automated reboot in order to activate the newly compiled `GENERIC.MP` kernel, but the `bin/build` command will automatically continue the build process. The high level tasks are as follows:

1. Download and extract the release tarball sources (`src.tar.gz`, `sys.tar.gz`, `xenocara.tar.gz`, and `ports.tar.gz`) to preload a CVS checkout
2. Update the source trees from CVS using the `OPENBSD_${MAJ}_${MIN}` tag (this is sometimes referred to as the `-stable` branch)
3. Build the `GENERIC` and `GENERIC.MP` kernels
4. Reboot to use the new kernel
5. Build userland
6. Run a `make release` to create the base release artifacts
7. Build X (a.k.a Xenocara)
8. Run a `make release` of Xenocara to create the X release artifacts
9. Create the combined `SHA256` checksum file
10. Sign the `SHA256` file to create `SHA256.sig` using your own *signify(1)* key
11. Create the final `index.txt`

As anyone who has rebuilt an entire OpenBSD release knows, this takes a "little while". Using a MacBook Pro 2.8 GHz Intel Core i7, building an OpenBSD 5.6 stable release of i386 took approximately 4 hours. This produces a directory structure that can be served up with a web server for further installations site-wide, for example:

```
pub/
└── OpenBSD
    └── 5.6
        └── i386
            ├── INSTALL.i386
            ├── SHA256
            ├── SHA256.sig
            ├── base56.tgz
            ├── bsd
            ├── bsd.mp
            ├── bsd.rd
            ├── cd56.iso
            ├── cdboot
            ├── cdbr
            ├── comp56.tgz
            ├── etc56.tgz
            ├── floppy56.fs
            ├── floppyB56.fs
            ├── floppyC56.fs
            ├── game56.tgz
            ├── index.txt
            ├── man56.tgz
            ├── miniroot56.fs
            ├── pxeboot
            ├── xbase56.tgz
            ├── xetc56.tgz
            ├── xfont56.tgz
            ├── xserv56.tgz
            └── xshare56.tgz

3 directories, 25 files
```

## Requirements

* [Vagrant](https://www.vagrantup.com/downloads.html)
* [VirtualBox](https://www.virtualbox.org/wiki/Downloads) or [VMware](https://www.vmware.com/go/downloadfusion)

## Usage

Clone this repository and enter the project directory:

```sh
git clone https://github.com/fnichol/openbsd-builder.git
cd openbsd-builder
```

Add your [signify(1)](http://www.openbsd.org/cgi-bin/man.cgi/OpenBSD-current/man1/signify.1?query=signify) keys to the `etc/signify` directory. The public key will replace the exiting `/etc/signify/openbsd-${OSrev}-base.pub` file in the new release and the `SHA256.sig` will be signed using the private key. This way, you can verify that the generated release was produced by your system/organization. In addition, the `cd${OSrev}.iso` and `floppy${OSrev}.fs` images will use your public key when verifying archives on new installs. For example, given a 5.6 build, these files must exist in your project:

```
etc/
└── signify
    ├── openbsd-56-stable-base.pub
    └── openbsd-56-stable-base.sec
```

If you have not previously generated keys, then you can generate them on an OpenBSD system with:

```sh
signify -G -n -p openbsd-56-stable-base.pub -s openbsd-56-stable-base.sec
```

Run the `bin/build` command with the version of OpenBSD (i.e. `5.6`) and the architecture (i.e. `amd64`), for example:

```sh
./bin/build 5.6 i386
```

Note that this takes multiple hours at a minimum. Currently only OpenBSD 5.6 (and greater) on `amd64` or `i386` architectures are supported.

## Building A Stable Branch-Based Vagrant Box

If further Vagrant boxes need to be created, you might consider using the OpenBSD packer templates from [fnichol/packer-templates](https://github.com/fnichol/packer-templates) which produced the Vagrant box which was used to build the release. I know, trippy, right?

For example, targeting the 5.6 release with your release artifacts hosted on a local web server called `http://mirror.example.com/pub/OpenBSD/5.6/i386`:

```sh
git clone https://github.com/fnichol/packer-templates.git
cd packer-templates
iso_checksum="`curl -s http://mirror.example.com/pub/OpenBSD/5.6/i386/SHA256 | grep cd56.iso | awk '{print $4}'`"
cat <<VARIABLES >openbsd-5.6-i386_variables.json
{
  "hostname": "openbsd-56-stable",
  "iso_checksum": "${iso_checksum}",
  "mirror_server": "mirror.example.com",
  "name": "openbsd-5.6-stable-i386"
}
VARIABLES
./bin/build openbsd-5.6-i386
```

How deliciously recursive...

## Development

* Source hosted at [GitHub][repo]
* Report issues/questions/feature requests on [GitHub Issues][issues]

Pull requests are very welcome! Make sure your patches are well tested.
Ideally create a topic branch for every separate change you make. For
example:

1. Fork the repo
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Authors

Created and maintained by [Fletcher Nichol][fnichol] (<fnichol@nichol.ca>)

## License

BSD 2-clause “Simplified” (see [LICENSE.txt][license])

[license]:      https://github.com/fnichol/openbsd-builder/blob/master/LICENSE.txt
[fnichol]:      https://github.com/fnichol
[repo]:         https://github.com/fnichol/openbsd-builder
[issues]:       https://github.com/fnichol/openbsd-builder/issues
