all:
	$(MAKE) core
	$(MAKE) git
	$(MAKE) http
	$(MAKE) mirage
	$(MAKE) unix

core:
	ocaml pkg/pkg.ml build -n irmin -q --tests true
	ocaml pkg/pkg.ml test

git:
	ocaml pkg/pkg.ml build -n irmin-git -q --tests true
	ocaml pkg/pkg.ml test

http:
	ocaml pkg/pkg.ml build -n irmin-http -q --tests true
	ocaml pkg/pkg.ml test

mirage:
	ocaml pkg/pkg.ml build -n irmin-mirage -q --tests true
	ocaml pkg/pkg.ml test

unix:
	ocaml pkg/pkg.ml build -n irmin-unix -q --tests true
	ocaml pkg/pkg.ml test

clean:
	ocaml pkg/pkg.ml clean -n irmin
	ocaml pkg/pkg.ml clean -n irmin-git
	ocaml pkg/pkg.ml clean -n irmin-http
	ocaml pkg/pkg.ml clean -n irmin-mirage
	ocaml pkg/pkg.ml clean -n irmin-unix
