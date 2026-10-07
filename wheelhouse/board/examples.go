// Package board holds the files that proj hands out.
package board

import _ "embed"

// ExampleProject is the commented project file that `proj init` leaves for reference.
//
//go:embed examples/project.yaml
var ExampleProject string

// ExampleReadme goes into the example project's folder.
//
//go:embed examples/example-readme.md
var ExampleReadme string
