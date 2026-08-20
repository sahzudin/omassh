.PHONY: test validate

test:
	python3 -m unittest discover -s tests -v

validate:
	omarchy plugin validate .
