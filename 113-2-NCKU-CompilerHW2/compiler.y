/* Please feel free to modify any content */

/* Definition section */
%{
    #include "compiler_common.h"
    // #define YYDEBUG 1
    // int yydebug = 1;

    extern int yylineno;
    extern int yylex();
    extern FILE *yyin;

    int yylex_destroy ();
    void yyerror (char const *s)
    {
        printf("error:%d: %s\n", yylineno, s);
    }

    extern int yylineno;
    extern int yylex();
    extern FILE *yyin;

    /* Symbol table function - you can add new functions if needed. */
    /* parameters and return type can be changed */
    #define MAX_BUFFER_SIZE 1024
    #define MAX_SYMBOLS 1024
    #define MAX_SCOPE 128

    typedef struct Symbol {
        char name[64];
        int mut;
        char type[16];
        int addr;
        int lineno;
        char func_sig[32];
    } Symbol;

    static char type_buffer[MAX_BUFFER_SIZE][128];
    static char operation_buffer[MAX_BUFFER_SIZE][64];
    static int type_buffer_index = 0;
    static int operation_buffer_index = 0;

    static void add_type_to_buffer(const char *type);
    static void add_operation_to_buffer(const char *operation);
    static void flush_type_buffer();
    static void flush_operation_buffer();

    static Symbol symbol_table[MAX_SCOPE][MAX_SYMBOLS];
    static int symbol_count[MAX_SCOPE] = {0};

    static int scope_level = -1;
    static int addr_counter = -1;
    static char current_type[16];

    static void create_symbol();
    static void insert_symbol(const char *name, const char *type, const char *func_sig, int mut);
    static int lookup_symbol(const char *name);
    static char* lookup_type(const char *name);
    static void dump_symbol();

    /* Global variables */
    bool HAS_ERROR = false;
%}

%error-verbose

/* Use variable or self-defined structure to represent
 * nonterminal and token type
 *  - you can add new fields if needed.
 */
%union {
    int i_val;
    float f_val;
    char *s_val;
    /* ... */
    char *type;
}

/* Token without return */
%token LET MUT NEWLINE
%token INT FLOAT BOOL STR
%token TRUE FALSE
%token GEQ LEQ EQL NEQ LOR LAND
%token ADD_ASSIGN SUB_ASSIGN MUL_ASSIGN DIV_ASSIGN REM_ASSIGN
%token IF ELSE FOR WHILE LOOP
%token PRINT PRINTLN
%token FUNC RETURN BREAK
%token ARROW AS IN DOTDOT RSHIFT LSHIFT

/* Token with return, which need to sepcify type */
%token <i_val> INT_LIT
%token <f_val> FLOAT_LIT
%token <s_val> STRING_LIT
%token <s_val> ID 

/*-------------------- Precedence & associativity ------------*/
%right '=' ADD_ASSIGN SUB_ASSIGN MUL_ASSIGN DIV_ASSIGN REM_ASSIGN
%left LOR
%left LAND
%left '|'
%left '&'
%left EQL NEQ
%left GEQ LEQ '>' '<'
%left LSHIFT RSHIFT
%left '+' '-'
%left '*' '/' '%'
%right UMINUS
%right '!' '~'

/* Nonterminal with return, which need to sepcify type */
%type <s_val> Type
// %type <s_val> Expression
// %type <s_val> TypeOpt
%type <i_val> MutOpt

/* Yacc will start at this nonterminal */
%start Program

/* Grammar section */
%%

Program
    : { create_symbol(); } GlobalStatementList { dump_symbol(); }
;

GlobalStatementList 
    : GlobalStatementList GlobalStatement
    | GlobalStatement
;

GlobalStatement
    : FunctionDeclStmt
    | NEWLINE
;

FunctionDeclStmt
    : FUNC ID { printf("func: %s\n", $2); insert_symbol($2, "func", "(V)V", -1); free($2);} '(' FunctionParamListOpt ')' ReturnTypeOpt Block
    ;

FunctionParamListOpt
    : /* empty */
    | FunctionParamList
    ;

FunctionParamList
    : FunctionParam
    | FunctionParamList ',' FunctionParam
    ;

FunctionParam
    : ID ':' Type
    ;

ReturnTypeOpt
    : /* empty */
    | ARROW Type
    ;

    ;

/*-------------------- Block & statements --------------------*/
Block
    : '{' { create_symbol(); } StatementListOpt '}' { dump_symbol(); }
    ;

StatementListOpt
    : /* empty */
    | StatementList
    ;

StatementList
    : Statement
    | StatementList Statement
    ;

Statement
    : LetDeclStmt
    | ExprStmt
    | RETURN Expression ';'
    | BREAK ';'
    | Block
    | PRINTLN '(' '"' STRING_LIT '"' ')' ';'    { printf("STRING_LIT \"%s\"\n", $4); printf("PRINTLN str\n"); free($4); }
    | PRINTLN '(' Expression ')' ';'            { printf("PRINTLN %s\n", current_type); }
    | PRINT '(' Expression ')' ';'              { printf("PRINT %s\n", current_type); }
    ;

LetDeclStmt
    : LET MutOpt ID ':' Type AssignOpt ';' { insert_symbol($3, $5, "-", $2); free($3); }
    ; //IDENT (name=x, address=0)

MutOpt
    : MUT               { $$ = 1; }
    | /* empty */       { $$ = 0; }
    ;

// TypeOpt
//     : ':' Type
//     | /* empty */
//     ;

AssignOpt
    : '=' Expression
    | /* empty */
    ;

Type
    : INT   { strcpy(current_type, "i32"); $$ = current_type; }
    | FLOAT { strcpy(current_type, "f32"); $$ = current_type; }
    | BOOL  { strcpy(current_type, "bool"); $$ = current_type; }
    | STR   { strcpy(current_type, "str"); $$ = current_type; }
    ;

ExprStmt
    : Expression ';'
    ;

/*-------------------- Expressions ---------------------------*/
Expression
    : Expression '+' Expression     { flush_type_buffer(); printf("ADD\n"); }
    | Expression '-' Expression     { flush_type_buffer(); printf("SUB\n"); }
    | Expression '*' Expression     { flush_type_buffer(); printf("MUL\n"); }
    | Expression '/' Expression     { flush_type_buffer(); printf("DIV\n"); }
    | Expression '%' Expression     { flush_type_buffer(); printf("REM\n"); }
    | Expression LSHIFT Expression
    | Expression RSHIFT Expression
    | Expression '>' Expression             { printf("GTR\n"); }
    | Expression '<' Expression             {  }
    | Expression GEQ Expression
    | Expression LEQ Expression
    | Expression EQL Expression
    | Expression NEQ Expression
    | Expression LAND Expression            { printf("LAND\n"); }
    | Expression LOR Expression             { printf("LOR\n"); }
    | '-' Expression        %prec UMINUS    { printf("NEG\n"); }
    | '!' Expression                        { { printf("NOT\n"); } }
    | '~' Expression                        // { $$ = $2; }
    | '(' Expression ')'                    // { $$ = $2; }
    | ID {
        char buffer[64];
        snprintf(buffer, sizeof(buffer), "IDENT (name=%s, address=%d)", $1, lookup_symbol($1));
        add_type_to_buffer(buffer);
    }
    | INT_LIT       { printf("INT_LIT %d\n", $1); strcpy(current_type, "i32"); }
    | FLOAT_LIT     { printf("FLOAT_LIT %f\n", $1); strcpy(current_type, "f32"); }
    | TRUE          { printf("bool TRUE\n"); strcpy(current_type, "bool"); }
    | FALSE         { printf("bool FALSE\n"); strcpy(current_type, "bool"); }
    ;

%%

/* C code section */
int main(int argc, char *argv[])
{
    if (argc == 2) {
        yyin = fopen(argv[1], "r");
    } else {
        yyin = stdin;
    }

    yylineno = 0;
    yyparse();

	printf("Total lines: %d\n", yylineno);
    fclose(yyin);
    return 0;
}

static void create_symbol() {
    ++scope_level;
    printf("> Create symbol table (scope level %d)\n", scope_level);
    // printf("> Create symbol table (scope level %d)\n", 0);
}

static void insert_symbol(const char *name, const char *type, const char *func_sig, int mut) {
    int index = symbol_count[scope_level]++;
    Symbol *sym = &symbol_table[scope_level][index];

    strncpy(sym->name, name, sizeof(sym->name));
    sym->mut = mut;
    strncpy(sym->type, type, sizeof(sym->type));
    sym->addr = addr_counter++;
    sym->lineno = yylineno+1;
    strncpy(sym->func_sig, func_sig, sizeof(sym->func_sig));

    printf("> Insert `%s` (addr: %d) to scope level %d\n", name, sym->addr, scope_level);
    // printf("> Insert `%s` (addr: %d) to scope level %d\n", name, addr_counter[scope_level]++, scope_level);
    // printf("> Insert `%s` (addr: %d) to scope level %d\n", "XXX", 0, 0);
}

static int lookup_symbol(const char *name) {
    for(int i=scope_level ; i>=0 ; --i){
        for(int j=0 ; j<symbol_count[i] ; ++j){
            Symbol *sym = &symbol_table[i][j];
            if(strcmp(sym->name, name) == 0){
                return sym->addr;
            }
        }
    }
    return -1;
}

static char* lookup_type(const char *name) {
    for(int i=scope_level ; i>=0; --i){
        for(int j=0 ; j<symbol_count[i] ; ++j){
            Symbol *sym = &symbol_table[i][j];
            if(strcmp(sym->name, name) == 0){
                return sym->type;
            }
        }
    }
    return NULL;
}

static void dump_symbol() {
    printf("\n> Dump symbol table (scope level: %d)\n", scope_level);
    // printf("\n> Dump symbol table (scope level: %d)\n", 0);
    printf("%-10s%-10s%-10s%-10s%-10s%-10s%-10s\n",
        "Index", "Name", "Mut","Type", "Addr", "Lineno", "Func_sig");

    for (int i = 0; i < symbol_count[scope_level]; ++i) {
        Symbol *sym = &symbol_table[scope_level][i];
        printf("%-10d%-10s%-10d%-10s%-10d%-10d%-10s\n",
            i, sym->name, sym->mut, sym->type, sym->addr, sym->lineno, sym->func_sig);
    }
    /* printf("%-10d%-10s%-10d%-10s%-10d%-10d%-10s\n",
            0, "name", 0, "type", 0, 0, "func_sig"); */

    --scope_level;
}

static void add_type_to_buffer(const char *type){
    strncpy(type_buffer[type_buffer_index], type, sizeof(type_buffer[type_buffer_index]));
    type_buffer_index++;
}
static void add_operation_to_buffer(const char *operation){
    strncpy(operation_buffer[operation_buffer_index], operation, sizeof(operation_buffer[operation_buffer_index]));
    operation_buffer_index++;
}
static void flush_type_buffer(){
    for(int i=0 ; i<type_buffer_index ; ++i){
        printf("%s\n", type_buffer[i]);
    }
    type_buffer_index = 0;
}
static void flush_operation_buffer(){
    for(int i=0 ; i<operation_buffer_index ; ++i){
        printf("%s\n", operation_buffer[i]);
    }
    operation_buffer_index = 0;
}