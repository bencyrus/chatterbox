package processing

import (
	"fmt"

	"github.com/bencyrus/chatterbox/worker/internal/types"
)

// Dispatcher routes tasks to registered processors by task type.
type Dispatcher struct {
	processors map[string]Processor
}

func NewDispatcher() *Dispatcher {
	return &Dispatcher{processors: map[string]Processor{}}
}

func (d *Dispatcher) Register(p Processor) {
	d.processors[p.TaskType()] = p
}

func (d *Dispatcher) Get(task *types.Task) (Processor, error) {
	p, ok := d.processors[task.TaskType]
	if !ok {
		return nil, fmt.Errorf("no processor registered for task type: %s", task.TaskType)
	}
	return p, nil
}
