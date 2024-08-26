# Default build
.PHONY: all
all: build

# Build the Swift package
.PHONY: build
build:
	swift build

# Test the Swift package
.PHONY: test
test:
	swift test

# Clean the build artifacts
.PHONY: clean
clean:
	swift package clean

# Generate documentation
.PHONY: doc
doc:
	swift package --allow-writing-to-directory ./docs \
	generate-documentation --target MoqLoc --output-path ./docs \
	--disable-indexing --transform-for-static-hosting --hosting-base-path swift-loc && \
	echo "<script>window.location.href += \"documentation/MoqLoc\"</script>" > docs/index.html
