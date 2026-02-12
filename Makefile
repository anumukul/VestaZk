.PHONY: verify-all cairo-check noir-check frontend-check deploy-sepolia devnet clean

verify-all: cairo-check noir-check frontend-check

cairo-check:
	@echo "Checking Cairo contracts..."
	cd contracts && \
	scarb fmt --check && \
	scarb build && \
	scarb test

noir-check:
	@echo "Checking Noir circuits..."
	cd circuits/borrow_proof && \
	nargo fmt --check && \
	nargo compile && \
	nargo test

frontend-check:
	@echo "Checking frontend..."
	cd frontend && \
	bun run type-check && \
	bun run lint && \
	bun test

deploy-sepolia:
	@echo "Deploying to Sepolia..."
	./scripts/deploy-sepolia.sh

devnet:
	@echo "Starting Starknet devnet..."
	starknet-devnet --seed 42 --host 127.0.0.1 --port 5050

clean:
	@echo "Cleaning build artifacts..."
	rm -rf contracts/target
	rm -rf circuits/*/target
	rm -rf frontend/.next
	rm -rf frontend/node_modules
	rm -rf frontend/.bun

install:
	@echo "Installing dependencies..."
	cd contracts && scarb build
	cd circuits/borrow_proof && nargo check
	cd frontend && bun install
