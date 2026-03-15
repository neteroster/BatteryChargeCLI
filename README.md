# btcharge

A minimal command-line tool to control and inspect battery charging on Apple Silicon Macs via SMC (System Management Controller).

## Requirements

- macOS 12 or later
- Apple Silicon Mac with a supported charging control SMC key
- Root privileges (`sudo`)

## Build

```bash
swift build -c release
```

The binary will be at `.build/release/btcharge`.

## Usage

```bash
# Disable charging (battery will not charge even when plugged in)
sudo btcharge off

# Re-enable charging
sudo btcharge on

# Show current charging key states
sudo btcharge show
```

Root privileges are required because accessing SMC keys needs direct hardware access.

## How It Works

`btcharge` communicates with the Apple SMC through IOKit to toggle charging control keys (`CHTE` / `CH0C`). It automatically detects which key your machine supports, writes the appropriate value, and verifies the result by reading it back.

## License

This project is licensed under the [BSD 3-Clause License](LICENSE).

Some included files are covered by their own licenses:

- `SMCParamStruct.h` — Apple Public Source License 2.0
- `MachTaskSelf.h` / `MachTaskSelf.c` — BSD 3-Clause (Marvin Haeuser)

See [THIRD-PARTY-NOTICES](THIRD-PARTY-NOTICES) for details.

## Acknowledgements

- [Battery-Toolkit](https://github.com/mhaeuser/Battery-Toolkit) by Marvin Häuser — the SMC communication code in this project is derived from Battery-Toolkit's implementation.
- [smcFanControl](https://github.com/hholtmann/smcFanControl) by Hendrik Holtmann — a valuable reference for understanding Apple SMC internals.
