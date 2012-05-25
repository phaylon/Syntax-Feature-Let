#include "EXTERN.h"
#include "perl.h"
#include "callchecker0.h"
#include "callparser.h"
#include "XSUB.h"

static OP *
myck_entersub_let (pTHX_ OP *entersubop, GV *namegv, SV *ckobj)
{
  OP *rv2cvop, *pushop, *blkop;

  PERL_UNUSED_ARG(namegv);
  PERL_UNUSED_ARG(ckobj);

  pushop = cUNOPx(entersubop)->op_first;
  if (!pushop->op_sibling)
    pushop = cUNOPx(pushop)->op_first;

  blkop = pushop->op_sibling;

  rv2cvop = blkop->op_sibling;
  blkop->op_sibling = NULL;
  pushop->op_sibling = rv2cvop;
  op_free(entersubop);

  return blkop;
}

#define SVt_PADNAME SVt_PVMG

#ifndef COP_SEQ_RANGE_LOW_set
# define COP_SEQ_RANGE_LOW_set(sv,val) \
	do { ((XPVNV*)SvANY(sv))->xnv_u.xpad_cop_seq.xlow = val; } while(0)
# define COP_SEQ_RANGE_HIGH_set(sv,val) \
	do { ((XPVNV*)SvANY(sv))->xnv_u.xpad_cop_seq.xhigh = val; } while(0)
#endif /* !COP_SEQ_RANGE_LOW_set */

#define pad_add_my_scalar_pvn(namepv, namelen, sv_type) \
		THX_pad_add_my_scalar_pvn(aTHX_ namepv, namelen, sv_type)
static PADOFFSET THX_pad_add_my_scalar_pvn(pTHX_
	char const *namepv, STRLEN namelen, int sv_type)
{
	PADOFFSET offset;
	SV *namesv, *myvar;
	myvar = *av_fetch(PL_comppad, AvFILLp(PL_comppad) + 1, 1);
    if (sv_type)
      SvUPGRADE(myvar, sv_type);
	offset = AvFILLp(PL_comppad);
	SvPADMY_on(myvar);
	PL_curpad = AvARRAY(PL_comppad);
	namesv = newSV_type(SVt_PADNAME);
	sv_setpvn(namesv, namepv, namelen);
	COP_SEQ_RANGE_LOW_set(namesv, PL_cop_seqmax);
	COP_SEQ_RANGE_HIGH_set(namesv, PERL_PADSEQ_INTRO);
	PL_cop_seqmax++;
	av_store(PL_comppad_name, offset, namesv);
	return offset;
}

#define pad_add_my_scalar_sv(namesv, sv_type) THX_pad_add_my_scalar_sv(aTHX_ namesv, sv_type)
static PADOFFSET THX_pad_add_my_scalar_sv(pTHX_ SV *namesv, int sv_type)
{
	char const *pv;
	STRLEN len;
	pv = SvPV(namesv, len);
	return pad_add_my_scalar_pvn(pv, len, sv_type);
}

#define parse_idword(prefix) THX_parse_idword(aTHX_ prefix)
static SV *
THX_parse_idword (pTHX_ char prefix)
{
	STRLEN prefixlen, idlen;
	SV *sv;
	char *start, *s, c;
	s = start = PL_parser->bufptr;
	c = *s;
	if(!isIDFIRST(c)) croak("syntax error");
	do {
		c = *++s;
	} while(isALNUM(c));
	lex_read_to(s);
	idlen = s-start;
	sv = sv_2mortal(newSV(1 + idlen));
	Copy(&prefix, SvPVX(sv), 1, char);
	Copy(start, SvPVX(sv)+1, idlen, char);
	SvPVX(sv)[1 + idlen] = 0;
	SvCUR_set(sv, 1 + idlen);
	SvPOK_on(sv);
	return sv;
}

#define DEMAND_IMMEDIATE 0x00000001
#define DEMAND_NOCONSUME 0x00000002
#define demand_unichar(c, f) THX_demand_unichar(aTHX_ c, f)
static void THX_demand_unichar(pTHX_ I32 c, U32 flags)
{
	if(!(flags & DEMAND_IMMEDIATE)) lex_read_space(0);
	if(lex_peek_unichar(0) != c) croak("syntax error");
	if(!(flags & DEMAND_NOCONSUME)) lex_read_unichar(0);
}

#define parse_varname() THX_parse_varname(aTHX)
static SV *
THX_parse_varname (pTHX)
{
  char sigil;

  sigil = lex_peek_unichar(0);
  switch (sigil) {
  case '$':
  case '@':
  case '%':
    lex_read_unichar(0);
    return parse_idword(sigil);
    break;
  default:
    croak("syntax error");
    break;
  }
}

#define mygenop_padsv(namesv, initop) THX_mygenop_padsv(aTHX_ namesv, initop)
static OP *
THX_mygenop_padsv (pTHX_ SV *namesv, OP *initop)
{
  OP *pvarop;
  int op_type;
  int sv_type = 0;

  switch (SvPV_nolen(namesv)[0]) {
  case '$':
    op_type = OP_PADSV;
    break;
  case '@':
    op_type = OP_PADAV;
    sv_type = SVt_PVAV;
    break;
  case '%':
    op_type = OP_PADHV;
    sv_type = SVt_PVHV;
    break;
  default:
    croak("oh no");
    break;
  }

  pvarop = newOP(op_type, (OPpLVAL_INTRO<<8));
  pvarop->op_targ = pad_add_my_scalar_sv(namesv, sv_type);
  return newASSIGNOP(OPf_STACKED, pvarop, 0, initop);
}

static OP *
myparse_args_let (pTHX_ GV *namegv, SV *psobj, U32 *flagsp)
{
  OP *initop = NULL, *blkop, *enterop, *leaveop;//, *nxtop;
  int blk_floor;
  AV *lexicals, *initargs;

  PERL_UNUSED_ARG(namegv);
  PERL_UNUSED_ARG(psobj);
  PERL_UNUSED_ARG(flagsp);

  blk_floor = Perl_block_start(aTHX_ 1);

  lex_read_space(0);
  while (lex_peek_unichar(0) == '(') {
    SV *varname;
    OP *initval;

    lex_read_unichar(0);
    varname = parse_varname();

    demand_unichar('=', 0);
    lex_read_space(0);

    initval = parse_listexpr(0);

    demand_unichar(')', 0);

    if (!initop)
      initop = mygenop_padsv(varname, initval);
    else
      initop = op_append_elem(OP_LINESEQ, initop,
                              mygenop_padsv(varname, initval));

    lex_read_space(0);
  }

  demand_unichar('{', DEMAND_NOCONSUME);

  blkop = op_append_elem(OP_LINESEQ, initop, parse_block(0));
  blkop = Perl_block_end(aTHX_ blk_floor, blkop);

  enterop = newOP(OP_ENTER, NULL);
  leaveop = newLISTOP(OP_LEAVE, NULL, blkop, NULL);
//  nxtop = newSTATEOP(NULL, NULL, NULL);

  cUNOPx(leaveop)->op_first = enterop;
  enterop->op_sibling = blkop;
//  enterop->op_sibling = nxtop;
//  nxtop->op_sibling = blkop;

  return leaveop;
}

MODULE = Syntax::Feature::Let  PACKAGE = Syntax::Feature::Let

void
let (...)
  CODE:
    PERL_UNUSED_ARG(items);
    croak("let called as a function");

BOOT:
{
  CV *let_cv;

  let_cv = get_cv("Syntax::Feature::Let::let", 0);

  cv_set_call_parser(let_cv, myparse_args_let, &PL_sv_undef);
  cv_set_call_checker(let_cv, myck_entersub_let, &PL_sv_undef);
}

