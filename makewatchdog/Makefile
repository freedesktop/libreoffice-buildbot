TIMEOUT=1000
#TIMEOUT=5

CXX=g++
CXXFLAGS=-O2

.PHONY: clean test_clean all test perform_test

all:
	$(CXX) -Wall $(CXXFLAGS) makewatchdog.cpp -o makewatchdog

test: all test_clean
	./makewatchdog 10 2 -- $(MAKE) -j2 perform_test

perform_test: first second

first: output
	cp output first

second: output2
	cp output2 second

output:
	( sleep 2; echo kukerr >&2; sleep $(TIMEOUT); echo kuk ) >output

output2:
	( sleep $(TIMEOUT); echo kuk ) >output2

test_clean:
	rm -f first second output output2 log

clean: test_clean
	rm -f makewatchdog
