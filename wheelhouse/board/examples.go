// Package board holds the files that proj hands out.
package board

import _ "embed"

// ExampleProject is the commented project file that `proj init` leaves as a template.
//
//go:embed examples/project.yaml
var ExampleProject string
