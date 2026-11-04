// Reads a MetricsQL query on stdin and prints it formatted by metricsql.Prettify.
package main

import (
	"fmt"
	"io"
	"os"

	"github.com/VictoriaMetrics/metricsql"
)

func main() {
	query, err := io.ReadAll(os.Stdin)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	formatted, err := metricsql.Prettify(string(query))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println(formatted)
}
