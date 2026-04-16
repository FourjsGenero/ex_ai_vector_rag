FORMS=\
 ai_rag_items.42f

PROGMOD=\
 ai_rag_items.42m

all: $(PROGMOD) $(FORMS)

%.42f: %.per
	fglform -M $<

%.42m: %.4gl
	fglcomp -Wall -Wno-stdsql -M $<

run:: all
	fglrun ai_rag_items.42m

clean::
	rm -f *.42?
