%{
# This routine has modified to use double precision values instead of single.
# Note that MAX_ARGS must be odd to insure structure alignment in A_OPS.

include	<lexnum.h>
include	<ctype.h>
include	<mach.h>
include	"fvexpr.h"

define	YYMAXDEPTH	64		# parser stack length
define	MAX_ARGS	17		# max args in a function call
define	yyparse		xfv_parse

define	DTOR		(($1)/57.2957795)
define	RTOD		(($1)*57.2957795)

# Arglist structure.
define	LEN_ARGSTRUCT	(1+MAX_ARGS+(MAX_ARGS*LEN_OPERAND))
define	A_NARGS		Memi[$1]	# number of arguments
define	A_ARGP		Memi[$1+$2]	# array of pointers to operand structs
define	A_OPS		($1+MAX_ARGS+1)	# offset to operand storage area

# Intrinsic functions.

define	KEYWORDS	"|abs|acos|asin|atan|atan2|bool|cos|exp|int|log|log10|\
			 |max|min|mod|nint|real|sin|sqrt|str|tan|"

define	F_ABS		01		# function codes
define	F_ACOS		02
define	F_ASIN		03
define	F_ATAN		04
define	F_ATAN2		05
define	F_BOOL		06
define	F_COS		07
define	F_EXP		08
define	F_INT		09
define	F_LOG		10
define	F_LOG10		11
	# newline	12
define	F_MAX		13
define	F_MIN		14
define	F_MOD		15
define	F_NINT		16
define	F_REAL		17
define	F_SIN		18
define	F_SQRT		19
define	F_STR		20
define	F_TAN 		21


# FVEXPR -- Evaluate an expression.  This is the top level procedure, and the
# only externally callable entry point.  Input consists of the expression to
# be evaluated (a string) and, optionally, user procedures for fetching
# external operands and executing external functions.  Output is a pointer to
# an operand structure containing the computed value of the expression.
# The output operand structure is dynamically allocated by FVEXPR and must be
# freed by the user.
#
# N.B.: this is not intended to be an especially efficient procedure.  Rather,
# this is a high level, easy to use procedure, intended to provide greater
# flexibility in the parameterization of applications programs.

pointer procedure fvexpr (expr, getop_epa, ufcn_epa)

char	expr[ARB]		# expression to be evaluated
int	getop_epa		# user supplied get operand procedure
int	ufcn_epa		# user supplied function call procedure

int	junk
bool	debug
pointer	sp, ip
int	xfv_gettok()
int	strlen(), xfv_parse()

errchk	xfv_parse, calloc
include	"fvexpr.com"
data	debug /false/

begin
	call smark (sp)

	# Set user function entry point addresses.
	fv_getop = getop_epa
	fv_ufcn  = ufcn_epa

	# Allocate an operand struct for the expression value.
	call calloc (fv_oval, LEN_OPERAND, TY_STRUCT)

	# Make a local copy of the input string.
	call salloc (ip, strlen(expr), TY_CHAR)
	call strcpy (expr, Memc[ip], ARB)

	# Evaluate the expression.  The expression value is copied into the
	# output operand structure by XFV_PARSE, given the operand pointer
	# passed in common.  A common must be used since the standard parser
	# subroutine has a fixed calling sequence.

	junk = xfv_parse (ip, debug, xfv_gettok)

	call sfree (sp)
	return (fv_oval)
end

%L
# XFV_PARSE -- SPP/Yacc parser for the evaluation of an expression passed as
# a text string.  Expression evaluation is carried out as the expression is
# parsed, rather than being broken into separate compile and execute stages.
# There is only one statement in this grammar, the expression.  Our function
# is to reduce an expression to a single value of type bool, string, int,
# or real.

pointer	ap
bool	streq()
errchk	zcall2, xfv_error1, xfv_unop, xfv_binop, xfv_boolop
errchk	xfv_quest, xfv_callfcn, xfv_addarg
include	"fvexpr.com"

%}

%token		CONSTANT IDENTIFIER NEWLINE YYEOS
%token		PLUS MINUS STAR SLASH EXPON CONCAT QUEST COLON
%token		LT GT LE GT EQ NE SE AND OR NOT AT

%nonassoc	QUEST
%left		OR
%left 		AND
%nonassoc	EQ NE SE
%nonassoc	LT GT LE GE
%left		CONCAT
%left		PLUS MINUS
%left		STAR SLASH
%left		EXPON
%right		UMINUS NOT
%right		AT

%%

stmt	:	expr YYEOS {
			# Normal exit.  Move the final expression value operand
			# into the operand structure pointed to by the global
			# variable fv_oval.

			YYMOVE ($1, fv_oval)
			return (OK)
		}
	|	error {
			call error (1, "syntax error")
		}
	;


expr	:	CONSTANT {
			# Numeric constant.
			YYMOVE ($1, $$)
		    }
	|	IDENTIFIER {
			# The boolean constants "yes" and "no" are implemented
			# as reserved operands.

			call xfv_initop ($$, 0, TY_BOOL)
			if (streq (O_VALC($1), "yes"))
			    O_VALB($$) = true
			else if (streq (O_VALC($1), "no"))
			    O_VALB($$) = false
			else if (fv_getop != NULL)
			    call zcall2 (fv_getop, O_VALC($1), $$)
			else
			    call xfv_error1 ("illegal operand `%s'", O_VALC($1))
			call xfv_freeop ($1)
		    }
	|	AT CONSTANT {
			# e.g., @"param"
			if (fv_getop != NULL)
			    call zcall2 (fv_getop, O_VALC($2), $$)
			else
			    call xfv_error1 ("illegal operand `%s'", O_VALC($2))
			call xfv_freeop ($2)
		    }
	|	MINUS expr %prec UMINUS {
			# Unary arithmetic minus.
			call xfv_unop (MINUS, $2, $$)
		    }
	|	NOT expr {
			# Boolean not.
			call xfv_unop (NOT, $2, $$)
		    }
	|	expr PLUS opnl expr {
			# Addition.
			call xfv_binop (PLUS, $1, $4, $$)
		    }
	|	expr MINUS opnl expr {
			# Subtraction.
			call xfv_binop (MINUS, $1, $4, $$)
		    }
	| 	expr STAR opnl expr {
			# Multiplication.
			call xfv_binop (STAR, $1, $4, $$)
		    }
	|	expr SLASH opnl expr {
			# Division.
			call xfv_binop (SLASH, $1, $4, $$)
		    }
	|	expr EXPON opnl expr {
			# Exponentiation.
			call xfv_binop (EXPON, $1, $4, $$)
		    }
	|	expr CONCAT opnl expr {
			# String concatenation.
			call xfv_binop (CONCAT, $1, $4, $$)
		    }
	|	expr AND opnl expr {
			# Boolean and.
			call xfv_boolop (AND, $1, $4, $$)
		    }
	|	expr OR opnl expr {
			# Boolean or.
			call xfv_boolop (OR, $1, $4, $$)
		    }
	|	expr LT opnl expr {
			# Boolean less than.
			call xfv_boolop (LT, $1, $4, $$)
		    }
	|	expr GT opnl expr {
			# Boolean greater than.
			call xfv_boolop (GT, $1, $4, $$)
		    }
	|	expr LE opnl expr {
			# Boolean less than or equal.
			call xfv_boolop (LE, $1, $4, $$)
		    }
	|	expr GE opnl expr {
			# Boolean greater than or equal.
			call xfv_boolop (GE, $1, $4, $$)
		    }
	|	expr EQ opnl expr {
			# Boolean equal.
			call xfv_boolop (EQ, $1, $4, $$)
		    }
	|	expr SE opnl expr {
			# String pattern-equal.
			call xfv_boolop (SE, $1, $4, $$)
		    }
	|	expr NE opnl expr {
			# Boolean not equal.
			call xfv_boolop (NE, $1, $4, $$)
		    }
	|	expr QUEST opnl expr COLON opnl expr {
			# Conditional expression.
			call xfv_quest ($1, $4, $7, $$)
		    }
	|	funct '(' arglist ')' {
			# Call an intrinsic or external function.
			ap = O_VALP($3)
			call xfv_callfcn (O_VALC($1),
			    A_ARGP(ap,1), A_NARGS(ap), $$)
			call mfree (ap, TY_STRUCT)
			call xfv_freeop ($1)
		    }
	|	'(' expr ')' {
			YYMOVE ($2, $$)
		    }
	;


funct	:	IDENTIFIER {
			YYMOVE ($1, $$)
		    }
	|	CONSTANT {
			if (O_TYPE($1) != TY_CHAR)
			    call error (1, "illegal function name")
			YYMOVE ($1, $$)
		    }
	;


arglist	:	{
			# Empty.
			call xfv_startarglist (NULL, $$)
		    }
	|	expr {
			# First arg; start a nonnull list.
			call xfv_startarglist ($1, $$)
		    }
	|	arglist ',' expr {
			# Add an argument to an existing list.
			call xfv_addarg ($3, $1, $$)
		    }
	;


opnl	:	# Empty.
	|	opnl NEWLINE
	;

%%


# XFV_UNOP -- Unary operation.  Perform the indicated unary operation on the
# input operand, returning the result as the output operand.

procedure xfv_unop (opcode, in, out)

int	opcode			# operation to be performed
pointer	in			# input operand
pointer	out			# output operand

errchk	xfv_error
define	badsw_ 91

begin
	call xfv_initop (out, 0, O_TYPE(in))

	switch (opcode) {
	case MINUS:
	    # Unary negation.
	    switch (O_TYPE(in)) {
	    case TY_BOOL, TY_CHAR:
		call xfv_error ("negation of a nonarithmetic operand")
	    case TY_INT:
		O_VALI(out) = -O_VALI(in)
	    case TY_DOUBLE:
		O_VALD(out) = -O_VALD(in)
	    default:
		goto badsw_
	    }

	case NOT:
	    switch (O_TYPE(in)) {
	    case TY_BOOL:
		O_VALB(out) = !O_VALB(in)
	    case TY_CHAR, TY_INT, TY_DOUBLE:
		call xfv_error ("not of a nonlogical")
	    default:
		goto badsw_
	    }

	default:
badsw_	    call xfv_error ("bad switch in unop")
	}
end


# XFV_BINOP -- Binary operation.  Perform the indicated arithmetic binary
# operation on the two input operands, returning the result as the output
# operand.

procedure xfv_binop (opcode, in1, in2, out)

int	opcode			# operation to be performed
pointer	in1, in2		# input operands
pointer	out			# output operand

double	r1, r2
int	i1, i2, dtype, nchars
int	xfv_newtype(), strlen()
errchk	xfv_newtype

begin
	# Set the datatype of the output operand, taking an error action if
	# the operands have incompatible datatypes.

	dtype = xfv_newtype (O_TYPE(in1), O_TYPE(in2))
	call xfv_initop (out, 0, dtype)

	switch (dtype) {
	case TY_BOOL:
	    call xfv_error ("operation illegal for boolean operands")
	case TY_CHAR:
	    if (opcode != CONCAT)
		call xfv_error ("operation illegal for string operands")
	case TY_INT:
	    i1 = O_VALI(in1)
	    i2 = O_VALI(in2)
	case TY_DOUBLE:
	    if (O_TYPE(in1) == TY_INT)
		r1 = O_VALI(in1)
	    else
		r1 = O_VALD(in1)
	    if (O_TYPE(in2) == TY_INT)
		r2 = O_VALI(in2)
	    else
		r2 = O_VALD(in2)
	default:
	    call xfv_error ("unknown datatype code in binop")
	}

	# Perform the operation.
	switch (opcode) {
	case PLUS:
	    if (dtype == TY_INT)
		O_VALI(out) = i1 + i2
	    else
		O_VALD(out) = r1 + r2

	case MINUS:
	    if (dtype == TY_INT)
		O_VALI(out) = i1 - i2
	    else
		O_VALD(out) = r1 - r2

	case STAR:
	    if (dtype == TY_INT)
		O_VALI(out) = i1 * i2
	    else
		O_VALD(out) = r1 * r2

	case SLASH:
	    if (dtype == TY_INT)
		O_VALI(out) = i1 / i2
	    else
		O_VALD(out) = r1 / r2

	case EXPON:
	    if (dtype == TY_INT)
		O_VALI(out) = i1 ** i2
	    else if (O_TYPE(in1) == TY_DOUBLE && O_TYPE(in2) == TY_INT)
		O_VALD(out) = r1 ** (O_VALI(in2))
	    else
		O_VALD(out) = r1 ** r2

	case CONCAT:
	    if (dtype != TY_CHAR)
		call xfv_error ("concatenation of a nonstring operand")
	    nchars = strlen (O_VALC(in1)) + strlen (O_VALC(in2))
	    call xfv_makeop (out, nchars, TY_CHAR)
	    call strcpy (O_VALC(in1), O_VALC(out), ARB)
	    call strcat (O_VALC(in2), O_VALC(out), ARB)
	    call xfv_freeop (in1)
	    call xfv_freeop (in2)

	default:
	    call xfv_error ("bad switch in binop")
	}
end


# XFV_BOOLOP -- Boolean binary operations.  Perform the indicated boolean binary
# operation on the two input operands, returning the result as the output
# operand.

procedure xfv_boolop (opcode, in1, in2, out)

int	opcode			# operation to be performed
pointer	in1, in2		# input operands
pointer	out			# output operand

bool	result
double	r1, r2
int	i1, i2, dtype
int	xfv_newtype(), xfv_patmatch(), strncmp()
errchk	xfv_newtype, xfv_error
define	badsw_ 91

begin
	# Set the datatype of the output operand, taking an error action if
	# the operands have incompatible datatypes.

	dtype = xfv_newtype (O_TYPE(in1), O_TYPE(in2))
	call xfv_initop (out, 0, dtype)

	switch (opcode) {
	case AND, OR:
	    if (dtype != TY_BOOL)
		call xfv_error ("AND or OR of nonlogical")
	case LT, GT, LE, GE:
	    if (dtype == TY_BOOL)
		call xfv_error ("order comparison of a boolean operand")
	}

	if (dtype == TY_INT) {
	    i1 = O_VALI(in1)
	    i2 = O_VALI(in2)
	} else if (dtype == TY_DOUBLE) {
	    if (O_TYPE(in1) == TY_INT) {
		i1 = O_VALI(in1)
		r1 = i1
	    } else
		r1 = O_VALD(in1)
	    if (O_TYPE(in2) == TY_INT) {
		i2 = O_VALI(in2)
		r2 = i2
	    } else
		r2 = O_VALD(in2)
	}

	# Perform the operation.
	switch (opcode) {
	case AND:
	    result = O_VALB(in1) && O_VALB(in2)
	case OR:
	    result = O_VALB(in1) || O_VALB(in2)

	case LT, GE:
	    if (dtype == TY_INT)
		result = i1 < i2
	    else if (dtype == TY_DOUBLE)
		result = r1 < r2
	    else
		result = strncmp (O_VALC(in1), O_VALC(in2), ARB) < 0
	    if (opcode == GE)
		result = !result

	case GT, LE:
	    if (dtype == TY_INT)
		result = i1 > i2
	    else if (dtype == TY_DOUBLE)
		result = r1 > r2
	    else
		result = strncmp (O_VALC(in1), O_VALC(in2), ARB) > 0
	    if (opcode == LE)
		result = !result

	case EQ, SE, NE:
	    switch (dtype) {
	    case TY_BOOL:
		if (O_VALB(in1))
		    result =  O_VALB(in2)
		else
		    result = !O_VALB(in2)
	    case TY_CHAR:
		if (opcode == SE)
		    result = xfv_patmatch (O_VALC(in1), O_VALC(in2)) > 0
		else
		    result = strncmp (O_VALC(in1), O_VALC(in2), ARB) == 0
	    case TY_INT:
		result = i1 == i2
	    case TY_DOUBLE:
		result = r1 == r2
	    default:
		goto badsw_
	    }
	    if (opcode == NE)
		result = !result

	default:
badsw_	    call xfv_error ("bad switch in boolop")
	}

	call xfv_makeop (out, 0, TY_BOOL)
	O_VALB(out) = result

	# Free storage if there were any string type input operands.
	call xfv_freeop (in1)
	call xfv_freeop (in2)
end


# XFV_PATMATCH -- Match a string against a pattern, returning the patmatch
# index if the string matches.  The pattern may contain any of the conventional
# pattern matching metacharacters.  Closure (i.e., "*") is mapped to "?*".

int procedure xfv_patmatch (str, pat)

char	str[ARB]		# operand string
char	pat[ARB]		# pattern

int	junk, ip, index
pointer	sp, patstr, patbuf, op
int	patmake(), patmatch()

begin
	call smark (sp)
	call salloc (patstr, SZ_FNAME, TY_CHAR)
	call salloc (patbuf, SZ_LINE,  TY_CHAR)

	# Map pattern, changing '*' into '?*'.
	op = patstr
	for (ip=1;  pat[ip] != EOS;  ip=ip+1) {
	    if (pat[ip] == '*') {
		Memc[op] = '?'
		op = op + 1
	    }
	    Memc[op] = pat[ip]
	    op = op + 1
	}

	# Encode pattern.
	junk = patmake (pat, Memc[patbuf], SZ_LINE)

	# Perform the pattern matching operation.
	index = patmatch (str, Memc[patbuf])

	call sfree (sp)
	return (index)
end


# XFV_NEWTYPE -- Get the datatype of a binary operation, given the datatypes
# of the two input operands.  An error action is taken if the datatypes are
# incompatible, e.g., boolean and anything else or string and anything else.

int procedure xfv_newtype (type1, type2)

int	type1, type2
int	newtype, p, q, i
int	tyindex[NTYPES], ttbl[NTYPES*NTYPES]
data	tyindex	/TY_BOOL, TY_CHAR,  TY_INT,  TY_DOUBLE/
data	(ttbl(i),i=1,4)		/TY_BOOL,       0,       0,        0/
data	(ttbl(i),i=5,8)		/      0, TY_CHAR,       0,        0/
data	(ttbl(i),i=9,12)	/      0,       0,  TY_INT,  TY_DOUBLE/
data	(ttbl(i),i=13,16)	/      0,       0, TY_DOUBLE,  TY_DOUBLE/

begin
	do i = 1, NTYPES {
	    if (tyindex[i] == type1)
		p = i
	    if (tyindex[i] == type2)
		q = i
	}

	newtype = ttbl[(p-1)*NTYPES+q]
	if (newtype == 0)
	    call xfv_error ("operands have incompatible types")
	else
	    return (newtype)
end


# XFV_QUEST -- Conditional expression.  If the condition operand is true
# return the first (true) operand, else return the second (false) operand.

procedure xfv_quest (cond, trueop, falseop, out)

pointer	cond			# pointer to condition operand
pointer	trueop, falseop		# pointer to true,false operands
pointer	out			# pointer to output operand
errchk	xfv_error

begin
	if (O_TYPE(cond) != TY_BOOL)
	    call xfv_error ("nonboolean condition operand")

	if (O_VALB(cond)) {
	    YYMOVE (trueop, out)
	    call xfv_freeop (falseop)
	} else {
	    YYMOVE (falseop, out)
	    call xfv_freeop (trueop)
	}
end


# XFV_CALLFCN -- Call an intrinsic function.  If the function named is not
# one of the standard intrinsic functions, call an external user function
# if a function call procedure was supplied.

procedure xfv_callfcn (fcn, args, nargs, out)

char	fcn[ARB]		# function to be called
pointer	args[ARB]		# pointer to arglist descriptor
int	nargs			# number of arguments
pointer	out			# output operand (function value)

double	rresult, rval[2], rtemp
int	iresult, ival[2], type[2], optype, oplen, itemp
int	opcode, v_nargs, i
pointer	sp, buf, ap
include	"fvexpr.com"

bool	strne()
int	strdic(), strlen()
errchk	zcall4, xfv_error1, xfv_error2, malloc
string	keywords KEYWORDS
define	badtype_ 91
define	free_ 92

begin
	call smark (sp)
	call salloc (buf, SZ_FNAME, TY_CHAR)

	oplen = 0

	# Lookup the function name in the dictionary.  An exact match is
	# required (strdic permits abbreviations).

	opcode = strdic (fcn, Memc[buf], SZ_FNAME, keywords)
	if (opcode > 0 && strne(fcn,Memc[buf]))
	    opcode = 0

	# If the function named is not a standard one and the user has supplied
	# the entry point of an external function evaluation procedure, call
	# the user procedure to evaluate the function, otherwise abort.

	if (opcode <= 0)
	    if (fv_ufcn != NULL) {
		call zcall4 (fv_ufcn, fcn, args, nargs, out)
		goto free_
	    } else
		call xfv_error1 ("unknown function `%s' called", fcn)

	# Verify correct number of arguments.
	switch (opcode) {
	case F_MOD:
	    v_nargs = 2
	case F_MAX, F_MIN, F_ATAN, F_ATAN2:
	    v_nargs = -1
	default:
	    v_nargs = 1
	}

	if (v_nargs > 0 && nargs != v_nargs)
	    call xfv_error2 ("function `%s' requires %d arguments",
		fcn, v_nargs)
	else if (v_nargs < 0 && nargs < abs(v_nargs))
	    call xfv_error2 ("function `%s' requires at least %d arguments",
		fcn, abs(v_nargs))

	# Verify datatypes.
	if (opcode != F_STR && opcode != F_BOOL) {
	    optype = TY_DOUBLE
	    do i = 1, min(2,nargs) {
		switch (O_TYPE(args[i])) {
		case TY_INT:
		    ival[i] = O_VALI(args[i])
		    rval[i] = ival[i]
		    type[i] = TY_INT
		case TY_DOUBLE:
		    rval[i] = O_VALD(args[i])
		    ival[i] = nint (rval[i])
		    type[i] = TY_DOUBLE
		default:
		    goto badtype_
		}
	    }
	}

	# Evaluate the function.

	ap = args[1]

	switch (opcode) {
	case F_ABS:
	    if (type[1] == TY_INT) {
		iresult = abs (ival[1])
		optype = TY_INT
	    } else
		rresult = abs (rval[1])

	case F_ACOS:
	    rresult = RTOD (acos (rval[1]))
	case F_ASIN:
	    rresult = RTOD (asin (rval[1]))
	case F_COS:
	    rresult =   cos (DTOR (rval[1]))
	case F_EXP:
	    rresult =   exp (rval[1])
	case F_LOG:
	    rresult =   log (rval[1])
	case F_LOG10:
	    rresult = log10 (rval[1])
	case F_SIN:
	    rresult =   sin (DTOR (rval[1]))
	case F_SQRT:
	    rresult =  sqrt (rval[1])
	case F_TAN:
	    rresult =   tan (DTOR (rval[1]))

	case F_ATAN, F_ATAN2:
	    if (nargs == 1)
		rresult = RTOD (atan (rval[1]))
	    else
		rresult = RTOD (atan2 (rval[1], rval[2]))

	case F_MOD:
	    if (type[1] == TY_DOUBLE || type[2] == TY_DOUBLE)
		rresult = mod (rval[1], rval[2])
	    else {
		iresult = mod (ival[1], ival[2])
		optype = TY_INT
	    }
		
	case F_NINT:
	    iresult = nint (rval[1])
	    optype = TY_INT

	case F_MAX, F_MIN:
	    # Determine datatype of result.
	    optype = TY_INT
	    do i = 1, nargs
		if (O_TYPE(args[i]) == TY_DOUBLE)
		    optype = TY_DOUBLE
		else if (O_TYPE(args[i]) != TY_INT)
		    goto badtype_

	    # Compute result.
	    if (optype == TY_INT) {
		iresult = O_VALI(ap)
		do i = 2, nargs {
		    itemp = O_VALI(args[i])
		    if (opcode == F_MAX)
			iresult = max (iresult, itemp)
		    else
			iresult = min (iresult, itemp)
		}

	    } else {
		if (O_TYPE(ap) == TY_INT)
		    rresult = O_VALI(ap)
		else
		    rresult = O_VALD(ap)

		do i = 2, nargs {
		    if (O_TYPE(args[i]) == TY_INT)
			rtemp = O_VALI(args[i])
		    else
			rtemp = O_VALD(args[i])
		    if (opcode == F_MAX)
			rresult = max (rresult, rtemp)
		    else
			rresult = min (rresult, rtemp)
		}
	    }

	case F_BOOL:
	    optype = TY_BOOL
	    switch (O_TYPE(ap)) {
	    case TY_BOOL:
		if (O_VALB(ap))
		    iresult = 1
		else
		    iresult = 0
	    case TY_CHAR:
		iresult = strlen (O_VALC(ap))
	    case TY_INT:
		iresult = O_VALI(ap)
	    case TY_DOUBLE:
		if (abs(rval[1]) > .001)
		    iresult = 1
		else
		    iresult = 0
	    default:
		goto badtype_
	    }

	case F_INT:
	    optype = TY_INT
	    if (type[1] == TY_INT)
		iresult = ival[1]
	    else
		iresult = rval[1]
		
	case F_REAL:
	    rresult = rval[1]

	case F_STR:
	    # Convert operand to operand of type string.

	    optype = TY_CHAR
	    switch (O_TYPE(ap)) {
	    case TY_BOOL:
		call malloc (iresult, 3, TY_CHAR)
		oplen = 3
		if (O_VALB(ap))
		    call strcpy ("yes", Memc[iresult], 3)
		else
		    call strcpy ("no",  Memc[iresult], 3)
	    case TY_CHAR:
		oplen = strlen (O_VALC(ap))
		call malloc (iresult, oplen, TY_CHAR)
		call strcpy (O_VALC(ap), Memc[iresult], ARB)
	    case TY_INT:
		oplen = MAX_DIGITS
		call malloc (iresult, oplen, TY_CHAR)
		call sprintf (Memc[iresult], SZ_FNAME, "%d")
		    call pargi (O_VALI(ap))
	    case TY_DOUBLE:
		oplen = MAX_DIGITS
		call malloc (iresult, oplen, TY_CHAR)
		call sprintf (Memc[iresult], SZ_FNAME, "%g")
		    call pargd (O_VALD(ap))
	    default:
		goto badtype_
	    }

	default:
	    call xfv_error ("bad switch in callfcn")
	}

	# Write the result to the output operand.  Bool results are stored in
	# iresult as an integer value, string results are stored in iresult as
	# a pointer to the output string, and integer and real results are
	# stored in iresult and rresult without any tricks.

	call xfv_initop (out, oplen, optype)

	switch (optype) {
	case TY_BOOL:
	    O_VALB(out) = (iresult != 0)
	case TY_CHAR:
	    O_VALP(out) = iresult
	case TY_INT:
	    O_VALI(out) = iresult
	case TY_DOUBLE:
	    O_VALD(out) = rresult
	}

free_
	# Free any storage used by the argument list operands.
	do i = 1, nargs
	    call xfv_freeop (args[i])

	call sfree (sp)
	return

badtype_
	call xfv_error1 ("bad argument to function `%s'", fcn)
	call sfree (sp)
	return
end


# XFV_STARTARGLIST -- Allocate an argument list descriptor to receive
# arguments as a function call is parsed.  We are called with either
# zero or one arguments.  The argument list descriptor is pointed to by
# a ficticious operand.  The descriptor itself contains a count of the
# number of arguments, an array of pointers to the operand structures,
# as well as storage for the operand structures.  The operands must be
# stored locally since the parser will discard its copy of the operand
# structure for each argument as the associated grammar rule is reduced.

procedure xfv_startarglist (arg, out)

pointer	arg			# pointer to first argument, or NULL
pointer	out			# output operand pointing to arg descriptor
pointer	ap

errchk	malloc

begin
	call xfv_initop (out, 0, TY_POINTER)
	call malloc (ap, LEN_ARGSTRUCT, TY_STRUCT)
	O_VALP(out) = ap

	if (arg == NULL)
	    A_NARGS(ap) = 0
	else {
	    A_NARGS(ap) = 1
	    A_ARGP(ap,1) = A_OPS(ap)
	    YYMOVE (arg, A_OPS(ap))
	}
end


# XFV_ADDARG -- Add an argument to the argument list for a function call.

procedure xfv_addarg (arg, arglist, out)

pointer	arg			# pointer to argument to be added
pointer	arglist			# pointer to operand pointing to arglist
pointer	out			# output operand pointing to arg descriptor

pointer	ap, o
int	nargs

begin
	ap = O_VALP(arglist)

	nargs = A_NARGS(ap) + 1
	A_NARGS(ap) = nargs
	if (nargs > MAX_ARGS)
	    call xfv_error ("too many function arguments")

	o = A_OPS(ap) + ((nargs - 1) * LEN_OPERAND)
	A_ARGP(ap,nargs) = o
	YYMOVE (arg, o)

	YYMOVE (arglist, out)
end


# XFV_ERROR1 -- Take an error action, formatting an error message with one
# format string plus one string argument.

procedure xfv_error1 (fmt, arg)

char	fmt[ARB]		# printf format string
char	arg[ARB]		# string argument
pointer	sp, buf

begin
	call smark (sp)
	call salloc (buf, SZ_LINE, TY_CHAR)

	call sprintf (Memc[buf], SZ_LINE, fmt)
	    call pargstr (arg)

	call xfv_error (Memc[buf])
	call sfree (sp)
end


# XFV_ERROR2 -- Take an error action, formatting an error message with one
# format string plus one string argument and one integer argument.

procedure xfv_error2 (fmt, arg1, arg2)

char	fmt[ARB]		# printf format string
char	arg1[ARB]		# string argument
int	arg2			# integer argument
pointer	sp, buf

begin
	call smark (sp)
	call salloc (buf, SZ_LINE, TY_CHAR)

	call sprintf (Memc[buf], SZ_LINE, fmt)
	    call pargstr (arg1)
	    call pargi (arg2)

	call xfv_error (Memc[buf])
	call sfree (sp)
end


# XFV_ERROR -- Take an error action, given an error message string as the
# sole argument.

procedure xfv_error (errmsg)

char	errmsg[ARB]			# error message

begin
	call error (1, errmsg)
end


# XFV_GETTOK -- Lexical analyzer for FVEXPR.  Returns the token code as the
# function value.  If the token is an operand (identifier or constant) the
# operand value is returned in OUT.

int procedure xfv_gettok (ip, out)

pointer	ip			# pointer into input string (expression)
pointer	out			# pointer to yacc YYLVAL token value operand

char	ch
long	lval
double	dval
pointer	ip_start
int	nchars, token, junk
int	stridx(), lexnum(), gctod(), gctol()
define	ident_ 91

begin
	while (IS_WHITE(Memc[ip]))
	    ip = ip + 1

	ch = Memc[ip]
	switch (ch) {
	case 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',      'J', 'K', 'L', 'M',
	     'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 
	     'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
	     'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z': 

	    # Return an identifier.
ident_
	    ip_start = ip
	    while (IS_ALNUM(ch) || stridx (ch, "_.$@#%&;[]\\^{}~") > 0) {
		ip = ip + 1
		ch = Memc[ip]
	    }

	    nchars = ip - ip_start
	    call xfv_initop (out, nchars, TY_CHAR)
	    call strcpy (Memc[ip_start], O_VALC(out), nchars)

	    return (IDENTIFIER)

	case 'I', '.', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
	    # Return a numeric constant.  The character I vectors here so
	    # that we can check for INDEF, a legal number.

	    token = lexnum (Memc, ip, nchars)
	    switch (token) {
	    case LEX_OCTAL:
		junk = gctol (Memc, ip, lval, 8)
		call xfv_initop (out, 0, TY_INT)
		O_VALI(out) = lval
	    case LEX_DECIMAL:
		junk = gctol (Memc, ip, lval, 10)
		call xfv_initop (out, 0, TY_INT)
		O_VALI(out) = lval
	    case LEX_HEX:
		junk = gctol (Memc, ip, lval, 16)
		call xfv_initop (out, 0, TY_INT)
		O_VALI(out) = lval
	    case LEX_REAL:
		junk = gctod (Memc, ip, dval)
		call xfv_initop (out, 0, TY_DOUBLE)
		if (IS_INDEFD (dval))
		    O_VALD(out) = INDEFD
		else
		    O_VALD(out) = dval
	    default:
		goto ident_
	    }

	    return (CONSTANT)

	case '\'', '"':
	    # Return a string constant.

	    ip_start = ip + 1
	    for (ip=ip+1;  Memc[ip] != ch && Memc[ip] != EOS;  ip=ip+1)
		;

	    nchars = ip - ip_start
	    if (Memc[ip] == EOS)
		call xfv_error ("missing closing quote in string constant")
	    else
		ip = ip + 1

	    call xfv_initop (out, nchars, TY_CHAR)
	    call strcpy (Memc[ip_start], O_VALC(out), nchars)

	    return (CONSTANT)

	case '+':
	    token = PLUS
	case '-':
	    token = MINUS
	case '*':
	    if (Memc[ip+1] == '*') {
		ip = ip + 1
		token = EXPON
	    } else
		token = STAR
	case '/':
	    if (Memc[ip+1] == '/') {
		ip = ip + 1
		token = CONCAT
	    } else
		token = SLASH

	case '?':
	    if (Memc[ip+1] == '=') {
		ip = ip + 1
		token = SE
	    } else
		token = QUEST

	case ':':
	    token = COLON

	case '@':
	    token = AT

	case '<':
	    if (Memc[ip+1] == '=') {
		ip = ip + 1
		token = LE
	    } else
		token = LT
	case '>':
	    if (Memc[ip+1] == '=') {
		ip = ip + 1
		token = GE
	    } else
		token = GT
	case '!':
	    if (Memc[ip+1] == '=') {
		ip = ip + 1
		token = NE
	    } else
		token = NOT
	case '=':
	    if (Memc[ip+1] == '=') {
		ip = ip + 1
		token = EQ
	    } else
		token = EQ
	case '&':
	    if (Memc[ip+1] == '&') {
		ip = ip + 1
		token = AND
	    } else
		token = AND
	case '|':
	    if (Memc[ip+1] == '|') {
		ip = ip + 1
		token = OR
	    } else
		token = OR

	case '(', ')', ',':
	    token = ch

	default:
	    if (ch == '\n')
		token = NEWLINE
	    else if (ch == EOS)
		token = YYEOS
	    else {
		# Anything we don't understand is assumed to be an identifier.
		goto ident_
	    }
	}

	ip = ip + 1
	return (token)
end


# XFV_INITOP -- Set up an unintialized operand structure.

procedure xfv_initop (o, o_len, o_type)

pointer	o		# pointer to operand structure
int	o_len		# length of operand (zero if scalar)
int	o_type		# datatype of operand

begin
	O_LEN(o) = 0
	call xfv_makeop (o, o_len, o_type)
end


# XFV_MAKEOP -- Set up the operand structure.  If the operand structure has
# already been initialized and array storage allocated, free the old array.

procedure xfv_makeop (o, o_len, o_type)

pointer	o		# pointer to operand structure
int	o_len		# length of operand (zero if scalar)
int	o_type		# datatype of operand

errchk	malloc

begin
	# Free old array storage if any.
	if (O_TYPE(o) != 0 && O_LEN(o) > 1) {
	    call mfree (O_VALP(o), O_TYPE(o))
	    O_LEN(o) = 0
	}

	# Set new operand type.
	O_TYPE(o) = o_type

	# Allocate array storage if nonscalar operand.
	if (o_len > 0) {
	    call malloc (O_VALP(o), o_len, o_type)
	    O_LEN(o) = o_len
	}
end


# XFV_FREEOP -- Reinitialize an operand structure, i.e., free any associated
# array storage and clear the operand datatype field, but do not free the
# operand structure itself (which may be only a segment of an array and not
# a separately allocated structure).

procedure xfv_freeop (o)

pointer	o		# pointer to operand structure

begin
	# Free old array storage if any.
	if (O_TYPE(o) != 0 && O_LEN(o) > 1) {
	    call mfree (O_VALP(o), O_TYPE(o))
	    O_LEN(o) = 0
	}

	# Clear the operand type to mark operand invalid.
	O_TYPE(o) = 0
end
