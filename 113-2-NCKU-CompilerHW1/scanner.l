/* Definition section */
%{
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>

    #define YY_NO_UNPUT
    #define YY_NO_INPUT
    #define print_token(token) \
        printf("%-8s \t %s\n", strcmp(token, "NEWLINE")? yytext: "", token)

    int line_num = 0;
    int comment_num = 0;
    int last_comment_line = -1;
%}


/* Flex state for multi-line comment */
%x COMMENT
%x STRINGBODY

/* Define regular expression label */
letter [a-zA-Z_]
digit [0-9]

int_lit     {digit}+
float_lit   {digit}+\.{digit}+
ident       {letter}({letter}|{digit})*

/* Rules section */
%%
\" {
    print_token("QUOTA");
    BEGIN(STRINGBODY);
}

<STRINGBODY>[^\"\n]+ {
    print_token("STRING_LIT");
}

<STRINGBODY>\" {
    print_token("QUOTA");
    BEGIN(INITIAL);
}

"//".* {
    if (line_num != last_comment_line) {
        comment_num++;
        last_comment_line = line_num;
    }
    print_token("COMMENT");
}

"/*" {
    BEGIN(COMMENT);
    if (line_num != last_comment_line) {
        comment_num++;
        last_comment_line = line_num;
    }
    printf("/*");
}

<COMMENT>"*/" {
    if (line_num != last_comment_line) {
        comment_num++;
        last_comment_line = line_num;
    }
    print_token("MUTI_LINE_COMMENT");
    BEGIN(INITIAL);
}

<COMMENT>\n {
    printf("\n");
    line_num++;
}

<COMMENT>. {
    printf("%s", yytext);
}

{int_lit}               { print_token("INT_LIT"); }
{float_lit}             { print_token("FLOAT_LIT"); }


{ident} {
    if (strcmp(yytext, "print") == 0) {
        print_token("PRINT");
    } else if (strcmp(yytext, "println") == 0) {
        print_token("PRINTLN");
    } else if (strcmp(yytext, "if") == 0) {
        print_token("IF");
    } else if (strcmp(yytext, "else") == 0) {
        print_token("ELSE");
    } else if (strcmp(yytext, "for") == 0) {
        print_token("FOR");
    } else if (strcmp(yytext, "i32") == 0) {
        print_token("INT");
    } else if (strcmp(yytext, "f32") == 0) {
        print_token("FLOAT");
    } else if (strcmp(yytext, "bool") == 0) {
        print_token("BOOL");
    } else if (strcmp(yytext, "true") == 0) {
        print_token("TRUE");
    } else if (strcmp(yytext, "false") == 0) {
        print_token("FALSE");
    } else if (strcmp(yytext, "let") == 0) {
        print_token("LET");
    } else if (strcmp(yytext, "mut") == 0) {
        print_token("MUT");
    } else if (strcmp(yytext, "fn") == 0) {
        print_token("FUNC");
    } else if (strcmp(yytext, "return") == 0) {
        print_token("RETURN");
    } else if (strcmp(yytext, "break") == 0) {
        print_token("BREAK");
    } else if (strcmp(yytext, "as") == 0) {
        print_token("AS");
    } else if (strcmp(yytext, "in") == 0) {
        print_token("IN");
    } else if (strcmp(yytext, "while") == 0) {
        print_token("WHILE");
    } else if (strcmp(yytext, "loop") == 0) {
        print_token("LOOP");
    } else {
        print_token("IDENT");
    }
}

"+"             { print_token("ADD"); }
"-"             { print_token("SUB"); }
"*"             { print_token("MUL"); }
"/"             { print_token("QUO"); }
"%"             { print_token("REM"); }
">"             { print_token("GTR"); }
"<"             { print_token("LSS"); }
">="            { print_token("GEQ"); }
"<="            { print_token("LEQ"); }
"=="            { print_token("EQL"); }
"!="            { print_token("NEQ"); }
"="             { print_token("ASSIGN"); }
"+="            { print_token("ADD_ASSIGN"); }
"-="            { print_token("SUB_ASSIGN"); }
"*="            { print_token("MUL_ASSIGN"); }
"/="            { print_token("QUO_ASSIGN"); }
"%="            { print_token("REM_ASSIGN"); }
"&"             { print_token("BAND"); }
"|"             { print_token("BOR"); }
"~"             { print_token("BNOT"); }
">>"            { print_token("RSHIFT"); }
"&&"            { print_token("LAND"); }
"||"            { print_token("LOR"); }
"!"             { print_token("NOT"); }
"("             { print_token("LPAREN"); }
")"             { print_token("RPAREN"); }
"["             { print_token("LBRACK"); }
"]"             { print_token("RBRACK"); }
"{"             { print_token("LBRACE"); }
"}"             { print_token("RBRACE"); }
";"             { print_token("SEMICOLON"); }
","             { print_token("COMMA"); }
\n              { print_token("NEWLINE"); line_num++; }
":"             { print_token("COLON"); }
"->"            { print_token("ARROW"); }
"<<"            { print_token("LSHIFT"); }
".."            { print_token("DOTDOT"); }

[ \t\r]+        { /* skip whitespace */ }

<<EOF>>         { line_num++; yyterminate(); }

%%

/*  C Code section */
int yywrap(void)
{
    return 1;
}

int main(int argc, char *argv[])
{
    if (argc == 2) {
        yyin = fopen(argv[1], "r");
    } else {
        yyin = stdin;
    }
    yylex();
    printf("\nFinish scanning,\n");
    printf("total line: %d\n", line_num);
    printf("comment line: %d\n", comment_num);
    fclose(yyin);
    return 0;
}