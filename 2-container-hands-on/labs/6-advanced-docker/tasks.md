## Lab 6: Complex Multi-Container Application

### Your Tasks

1. Build and deploy a 3-tier application (frontend, backend, database)
2. Implement network segmentation for security
3. Set up health checks and service dependencies
4. Test scaling individual components
5. Verify data persistence

### Challenge Questions

- How do you prevent the frontend from directly accessing the database?
- What's the difference between building images vs. using pre-built ones?
- How do you ensure services start in the correct order?

### Success Criteria

- [ ] All three tiers are running and communicating
- [ ] Frontend cannot directly reach database
- [ ] Can scale backend without affecting other services
- [ ] Health checks show all services are healthy
- [ ] Application data survives application restart
