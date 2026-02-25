# Signal & Background Validation

Jupyter notebooks for validating the H → Za signal and background samples.

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install awkward uproot vector hist mplhep coffea ipykernel
```

Then VSCode can pick up the virtual environment for executing the notebook.

## Notebooks

| Notebook | Description |
|----------|-------------|
| `signal_validation.ipynb` | Gen-level checks, Z/a/H reconstruction from PF candidates |
