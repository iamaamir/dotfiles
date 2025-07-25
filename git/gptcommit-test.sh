TMP=$(mktemp)
bash ./gptcommit.sh "$TMP" commit
echo "------------------------------ generated file ------------------------"
cat "$TMP"                                        # see generated draft
rm "$TMP"
