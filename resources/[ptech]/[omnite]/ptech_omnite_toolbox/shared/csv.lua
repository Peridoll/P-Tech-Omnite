OmniteCsv = {}
function OmniteCsv.encode(headers, rows)
    local function field(value)
        return '"'..tostring(value or ''):gsub('"','""')..'"'
    end
    local lines={table.concat(headers,',')}
    for _,row in ipairs(rows) do
        local fields={}
        for _,key in ipairs(headers) do fields[#fields+1]=field(row[key]) end
        lines[#lines+1]=table.concat(fields,',')
    end
    return table.concat(lines,'\r\n')
end
function OmniteCsv.decode(text, headers)
    assert(type(text)=='string' and #text<=2000000,'CSVは2MB以下にしてください。')
    text=text:gsub('^\239\187\191','')
    local records,row,buffer={}, {}, ''
    local quoted,closed,start=false,false,true
    local i=1
    local function cell() row[#row+1]=buffer buffer='' closed=false start=true end
    local function record()
        cell()
        if #row>1 or row[1]~='' then records[#records+1]=row end
        row={}
        assert(#records<=1001,'CSVは1000行以下にしてください。')
    end
    while i<=#text do
        local c=text:sub(i,i)
        if quoted then
            if c=='"' then
                if text:sub(i+1,i+1)=='"' then buffer=buffer..'"' i=i+1
                else quoted=false closed=true end
            else buffer=buffer..c end
        elseif c=='"' and start then quoted=true start=false
        elseif c==',' then cell()
        elseif c=='\n' or c=='\r' then
            record()
            if c=='\r' and text:sub(i+1,i+1)=='\n' then i=i+1 end
        else
            assert(not closed and c~='"','CSVの引用符が不正です。')
            buffer=buffer..c start=false
        end
        i=i+1
    end
    assert(not quoted,'CSVの引用符が閉じていません。')
    if #row>0 or buffer~='' or closed then record() end
    local header=table.remove(records,1)
    assert(header and #header==#headers,'CSVの列数が違います。')
    for n,key in ipairs(headers) do assert(header[n]==key,'CSVヘッダーが違います: '..key) end
    local output={}
    for n,values in ipairs(records) do
        assert(#values==#headers,'CSV '..n..'行目の列数が違います。')
        local entry={}
        for index,key in ipairs(headers) do entry[key]=values[index] end
        output[#output+1]=entry
    end
    return output
end
