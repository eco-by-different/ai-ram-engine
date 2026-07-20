![Repo size](https://img.shields.io/github/repo-size/eco-by-different/ai-ram-engine)
![Last commit](https://img.shields.io/github/last-commit/eco-by-different/ai-ram-engine)

# AI RAM Engine

Lightweight system optimization tool for managing CPU, memory and power efficiency.

AI RAM Engine is a PowerShell-based system optimization tool designed to improve performance under heavy workloads such as video encoding.

---

## Features

- CPU priority control
- Memory priority management
- Power throttling (Windows efficiency mode)
- ECO / PERFORMANCE mode
- Process-level optimization

---

## Requirements

- Windows 10 / 11
- PowerShell
- Administrator privileges (recommended)

## Usage

Run PowerShell as Administrator:

```powershell
.\ai-ram-engine.ps1
```

## Notes

Some optimizations (e.g. process priority and power throttling)  
may not apply correctly without administrator privileges.

## Development

This project was developed with the assistance of AI tools.

All design decisions, testing and system-level behavior were manually verified
and adjusted for real-world use.

## Recent Updates

- Rebuilt with a lightweight launcher to reduce file size and eliminate the console window
- Enhanced Performance: Optimized core engine logic for better RAM and CPU resource allocation.
- Memory Efficiency: Improved dynamic memory management under heavy workloads like video encoding.
- Stability: Refined code structure to prevent crashes and ensure smoother script execution.

## License

MIT License

Copyright (c) 2026 Jan Simak

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
