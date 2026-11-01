package config

// LabelExecutionPolicy contains validated weights applied only to complete
// source evidence. Missing evidence remains a SQL NULL regardless of policy.
type LabelExecutionPolicy struct {
	EntryCeilingWeight   float64 `json:"entry_ceiling_weight"`
	MultipleLockedWeight float64 `json:"multiple_locked_weight"`
}

func (c Config) LabelExecutionPolicy() (LabelExecutionPolicy, error) {
	if err := c.Validate(); err != nil {
		return LabelExecutionPolicy{}, err
	}
	entry, err := c.number("labels", "entry_ceiling_weight")
	if err != nil {
		return LabelExecutionPolicy{}, err
	}
	locked, err := c.number("labels", "multiple_locked_weight")
	if err != nil {
		return LabelExecutionPolicy{}, err
	}
	return LabelExecutionPolicy{EntryCeilingWeight: entry, MultipleLockedWeight: locked}, nil
}
