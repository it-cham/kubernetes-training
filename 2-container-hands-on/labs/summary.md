# Module 2: Lab Tasks - Student Worksheet

## Lab 7: Experiencing Single-Host Limitations

### Your Tasks

1. Push your single-host setup to its limits
2. Simulate various failure scenarios
3. Identify operational challenges
4. Document the problems you encounter

### Challenge Questions

- What happens when you try to scale beyond your machine's capacity?
- How would you handle a server failure in production?
- What manual steps would be needed to maintain this setup?

### Success Criteria

- [ ] Identify at least 3 limitations of single-host deployment
- [ ] Experience resource exhaustion or conflicts
- [ ] Understand why manual scaling doesn't scale

---

## Helpful Hints

### When you get stuck

- Use `--help` flag with any Docker command
- Check container logs when things don't work
- Use `docker ps` and `docker inspect` to debug
- Ask your instructor or pair with someone nearby

### Common starting points

- Most Docker commands follow the pattern: `docker [command] [options] [image/container]`
- YAML files are sensitive to indentation (use spaces, not tabs)
- Container names must be unique
- Ports are mapped as `host:container`

### Debugging commands you might need

- `docker ps -a` (show all containers)
- `docker logs [container]` (see what went wrong)
- `docker inspect [container/network/volume]` (detailed info)

---

## Lab Completion Checklist

Mark off each lab as you complete it:

- [ ] Lab 1: Docker Installation & Verification
- [ ] Lab 2: Basic Container Operations
- [ ] Lab 3: Container Networking & Communication
- [ ] Lab 4: Container Storage Management
- [ ] Lab 5: First Docker Compose Application
- [ ] Lab 6: Complex Multi-Container Application
- [ ] Lab 7: Experiencing Single-Host Limitations
