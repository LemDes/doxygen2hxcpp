# [work in progress] doxygen2hxcpp

Generate hxcpp externs using doxygen xml output.

## Usage

If you wish to test (the externs aren't yet working):

* Add a `wxWidgets-master` folder using [https://github.com/wxWidgets/wxWidgets/archive/master.zip](https://github.com/wxWidgets/wxWidgets/archive/master.zip)

* Modify `docs/doxygen/Doxyfile` line 478 to `GENERATE_XML = YES`

* Make the doxygen doc with `doxygen Doxyfile` (in docs/doxygen/)

* `haxe build.hxml`

Now you can look into the output folder.

## License

Copyright (c) 2015 Valentin Lemière, Guillaume Desquesnes

doxygen2hxcpp is licensed under the GPLv3, see LICENSE.md for more details.
