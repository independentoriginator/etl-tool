<?xml version="1.0"?>

<!-- XSL Transformation: SpreadsheetML -> Simple list of cells -->
<!-- Output format: delimiter-separated values (DSV) -->

<xsl:stylesheet 
	version="2.0" 
	xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
	xmlns:xs="http://www.w3.org/2001/XMLSchema"
	xmlns:local="http://localhost/xsl/definitions"
	xmlns:main="http://schemas.openxmlformats.org/spreadsheetml/2006/main" 
	xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
	xmlns:pkg_rel="http://schemas.openxmlformats.org/package/2006/relationships"	
	exclude-result-prefixes="local main"
>
	<xsl:output method="text"/>
	
	<xsl:param name="delimiter" select="';'"/>
	<xsl:param name="quotationMark" select="'&quot;'"/>
	<xsl:param name="lineBreak" select="'&#xA;'"/><!-- Line feed -->	
	<xsl:param name="withHeader" select="'true'"/>

	<xsl:param name="sourceFileName"/>
	<xsl:param name="sourceFileId"/>
	<xsl:param name="sourceArchiveName"/>
	
	<xsl:variable name="local:date1904">
		<!-- "1904 Date System" is used for compatibility with Excel 2008 for Mac and earlier Mac versions -->
		<xsl:choose>				
			<xsl:when test="matches(/main:workbook/main:workbookPr/@date1904, '(true|1|on)')">
				<xsl:value-of select="true()"/>
			</xsl:when>				
			<xsl:otherwise>
				<xsl:value-of select="false()"/>				
			</xsl:otherwise>				
		</xsl:choose>				
	</xsl:variable>

	<xsl:template match="/">
	
		<xsl:variable name="fileDirectory">
			<xsl:call-template name="parentDirectory">
				<xsl:with-param name="filePath" select="base-uri()" />
			</xsl:call-template>			
		</xsl:variable>
		
		<xsl:variable 
			name="sharedStringsFilePath"
			select="
				concat(
					$fileDirectory, 
					'/',
					document(
						concat(
							$fileDirectory, 
							'/_rels/workbook.xml.rels'
						)
					)/pkg_rel:Relationships/pkg_rel:Relationship[@Type='http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings']/@Target
				)
			"/>

		<xsl:variable 
			name="stylesFilePath"
			select="
				concat(
					$fileDirectory, 
					'/',
					document(
						concat(
							$fileDirectory, 
							'/_rels/workbook.xml.rels'
						)
					)/pkg_rel:Relationships/pkg_rel:Relationship[@Type='http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles']/@Target
				)
			"/>
		
		<xsl:if test="$withHeader='true'">
			<xsl:variable name="destFileHeader" as="xs:string*">
				<xsl:sequence
					select="(
						'bookId', 'sheetId', 'row', 'col', 'columnAlpha', 'hidden', 'formula', 'format', 'type', 'value'
					)"/>
			</xsl:variable>
			<xsl:value-of select="string-join($destFileHeader, $delimiter)"/>
			<xsl:value-of select="$lineBreak"/>
		</xsl:if>		

		<xsl:result-document href="books.csv" method="text">
			<xsl:if test="$withHeader='true'">
				<xsl:variable name="destFileHeader" as="xs:string*">
					<xsl:sequence
						select="(
							'bookId', 'bookName', 'sourceArchiveName', 'date1904'
						)"/>
				</xsl:variable>
				<xsl:value-of select="string-join($destFileHeader, $delimiter)"/>
				<xsl:value-of select="$lineBreak"/>
			</xsl:if>		
		
			<xsl:call-template name="DSValue">
				<!-- bookId -->
				<xsl:with-param name="value" select="$sourceFileId" />
			</xsl:call-template>			
			<xsl:call-template name="DSValue">
				<!-- bookName -->
				<xsl:with-param name="value" select="$sourceFileName" />
			</xsl:call-template>
			<xsl:call-template name="DSValue">
				<!-- sourceArchiveName -->
				<xsl:with-param name="value" select="$sourceArchiveName" />
			</xsl:call-template>		
			<xsl:call-template name="DSValue">
				<!-- date1904 -->
				<xsl:with-param name="value" select="$local:date1904" />
				<xsl:with-param name="isLastField" select="'true'" />
			</xsl:call-template>			
			
			<xsl:value-of select="$lineBreak"/>
        </xsl:result-document>	

		<xsl:result-document href="sheets.csv" method="text">
			<xsl:if test="$withHeader='true'">
				<xsl:variable name="destFileHeader" as="xs:string*">
					<xsl:sequence
						select="(
							'bookId', 'sheetId', 'sheetName', 'sheetHidden'
						)"/>
				</xsl:variable>
				<xsl:value-of select="string-join($destFileHeader, $delimiter)"/>
				<xsl:value-of select="$lineBreak"/>
			</xsl:if>		
		
			<xsl:for-each select="main:workbook/main:sheets/main:sheet">
				<xsl:call-template name="DSValue">
					<!-- bookId -->
					<xsl:with-param name="value" select="$sourceFileId" />
				</xsl:call-template>			
				<xsl:call-template name="DSValue">
					<!-- sheetId -->
					<xsl:with-param name="value" select="@sheetId" />
				</xsl:call-template>			
				<xsl:call-template name="DSValue">
					<!-- sheetName -->
					<xsl:with-param name="value" select="@name" />
				</xsl:call-template>		
				<xsl:variable name="sheetHidden">
					<xsl:choose>				
						<xsl:when test="matches(@state, '(hidden|veryHidden)')">
							<xsl:value-of select="true()"/>
						</xsl:when>				
						<xsl:otherwise>
							<xsl:value-of select="false()"/>						
						</xsl:otherwise>				
					</xsl:choose>				
				</xsl:variable>
				<xsl:call-template name="DSValue">
					<!-- sheetHidden -->
					<xsl:with-param name="value" select="$sheetHidden" />
					<xsl:with-param name="isLastField" select="'true'" />
				</xsl:call-template>			
				
				<xsl:value-of select="$lineBreak"/>
			</xsl:for-each>
        </xsl:result-document>	
		
		<xsl:apply-templates select="main:workbook/main:sheets/main:sheet">
			<xsl:with-param name="fileDirectory" select="$fileDirectory"/>
			<xsl:with-param name="sharedStringsFilePath" select="$sharedStringsFilePath"/>
			<xsl:with-param name="stylesFilePath" select="$stylesFilePath"/>
		</xsl:apply-templates>		
		
	</xsl:template>
	
	<xsl:template match="main:sheet">
	
		<xsl:param name="fileDirectory"/>
		<xsl:param name="sharedStringsFilePath"/>
		<xsl:param name="stylesFilePath"/>
		
		<xsl:variable 
			name="sheetFilePath"
			select="
				concat(
					$fileDirectory, 
					'/',
					document(
						concat(
							$fileDirectory, 
							'/_rels/workbook.xml.rels'
						)
					)/pkg_rel:Relationships/pkg_rel:Relationship[@Id=current()/@r:id]/@Target
				)
			"/>
		
		<xsl:variable name="hiddenColumns">
			<xsl:for-each 
				select="
					document(
						$sheetFilePath
					)/main:worksheet/main:cols/main:col[@hidden = 'true']
				">
				<xsl:variable name="colNumSeq" as="xs:integer*" select="@min to @max"/>	
				<xsl:value-of select="$colNumSeq" separator=","/><xsl:text>,</xsl:text>
			</xsl:for-each>
		</xsl:variable>
		
		<xsl:apply-templates 
			select="
				document(
					$sheetFilePath
				)/main:worksheet/main:sheetData/main:row
			">
			<xsl:with-param name="sharedStringsFilePath" select="$sharedStringsFilePath"/>			
			<xsl:with-param name="stylesFilePath" select="$stylesFilePath"/>						
			<xsl:with-param name="sheetId" select="@sheetId" />
			<xsl:with-param name="hiddenColumns" select="$hiddenColumns" />
		</xsl:apply-templates>			
			
	</xsl:template>
	
	<xsl:template match="main:row">
	
		<xsl:param name="sharedStringsFilePath"/>
		<xsl:param name="stylesFilePath"/>
		<xsl:param name="sheetId"/>
		<xsl:param name="hiddenColumns"/>
		
		<xsl:for-each select="main:c">
		
			<xsl:call-template name="DSValue">
				<!-- bookId -->
				<xsl:with-param name="value" select="$sourceFileId" />
			</xsl:call-template>			
			<xsl:call-template name="DSValue">
				<!-- sheetId -->
				<xsl:with-param name="value" select="$sheetId" />
			</xsl:call-template>			
			<xsl:call-template name="DSValue">
				<!-- row -->
				<xsl:with-param name="value" select="../@r" />
			</xsl:call-template>			
			<xsl:variable name="columnAlpha" select="replace(@r, '(\d+)$', '')"/>				
			<xsl:variable name="columnNumber">								
				<xsl:call-template name="alpha2Number">
					<xsl:with-param name="string" select="$columnAlpha" />
				</xsl:call-template>			
			</xsl:variable>
			<xsl:call-template name="DSValue">
				<!-- col -->
				<xsl:with-param name="value" select="$columnNumber" />
			</xsl:call-template>			
			<xsl:call-template name="DSValue">
				<!-- columnAlpha -->
				<xsl:with-param name="value" select="$columnAlpha" />
			</xsl:call-template>			

			<xsl:variable name="hidden">								
				<xsl:choose>				
					<xsl:when test="../@hidden = 'true'">
						<xsl:value-of select="'true'"/>				
					</xsl:when>				
					<xsl:when test="contains($hiddenColumns, concat($columnNumber, ','))">
						<xsl:value-of select="'true'"/>				
					</xsl:when>				
					<xsl:otherwise>
						<xsl:value-of select="'false'"/>				
					</xsl:otherwise>				
				</xsl:choose>				
			</xsl:variable>
			<xsl:call-template name="DSValue">
				<!-- hidden -->
				<xsl:with-param name="value" select="$hidden" />
			</xsl:call-template>			
			
			<xsl:call-template name="DSValue">
				<!-- formula -->
				<xsl:with-param name="value" select="main:f" />
			</xsl:call-template>			

			<xsl:variable name="formatRef" select="@s"/>								
			<xsl:variable name="formatCode">
				<xsl:if test="$formatRef">
					<xsl:value-of 
						select="
							document(
								'number-formats.xml'
							)/numFmts/numFmt[
								@numFmtId = 
									document(
										$stylesFilePath
									)/main:styleSheet/main:cellXfs/main:xf[position() = current()/@s + 1]/@numFmtId
							]
						"/>				
				</xsl:if>
			</xsl:variable>
			<xsl:variable name="customFormatCode">								
				<xsl:if test="$formatRef != '' and $formatCode = ''">
					<xsl:value-of 
						select="
							document(
								$stylesFilePath
							)/main:styleSheet/main:numFmts/main:numFmt[@numFmtId = /main:styleSheet/main:cellXfs/main:xf[position() = current()/@s + 1]/@numFmtId]/@formatCode
						"/>
				</xsl:if>
			</xsl:variable>
			<xsl:variable name="format">								
				<xsl:choose>				
					<xsl:when test="$formatCode != ''">
						<xsl:value-of select="$formatCode"/>				
					</xsl:when>				
					<xsl:when test="$customFormatCode != ''">
						<xsl:value-of select="$customFormatCode"/>				
					</xsl:when>				
					<xsl:otherwise>
						<xsl:value-of 
							select="
								document(
									$stylesFilePath
								)/main:styleSheet/main:cellXfs/main:xf[position() = current()/@s + 1]/@numFmtId								
							"/>				
					</xsl:otherwise>				
				</xsl:choose>							
			</xsl:variable>
			<xsl:call-template name="DSValue">
				<!-- format -->
				<xsl:with-param name="value" select="$format" />
			</xsl:call-template>			

			<xsl:variable name="rawType" select="@t">	
				<!--
					Possible values include:
					- b for boolean
					- d for date
					- e for error
					- inlineStr for an inline string (i.e., not stored in the shared strings part, but directly in the cell)
					- n for number
					- s for shared string (so stored in the shared strings part and not in the cell)
					- str for a formula (a string representing the formula)
				-->
			</xsl:variable>
			<xsl:variable name="type">
				<xsl:choose>				
					<xsl:when test="matches($rawType, '[ndbs]')">
						<xsl:value-of select="$rawType"/>				
					</xsl:when>				
					<xsl:when test="matches($formatCode, '[dmy]{2}', 'i') or matches($customFormatCode, '[dmy]{2}', 'i')">
						<xsl:value-of select="'d'"/>				
					</xsl:when>				
					<xsl:when test="matches($rawType, '(str|inlineStr|e)')">
						<xsl:value-of select="'s'"/>				
					</xsl:when>				
					<xsl:otherwise>
						<xsl:value-of select="'n'"/>				
					</xsl:otherwise>				
				</xsl:choose>	
			</xsl:variable>
			
			<xsl:call-template name="DSValue">
				<!-- type -->
				<xsl:with-param name="value" select="$type" />
			</xsl:call-template>			

			<xsl:variable name="rawValue" select="./main:v"/>					
			<xsl:variable name="value">	
				<xsl:choose>				
					<!-- number -->
					<xsl:when test="$type = 'n'">
						<xsl:value-of select="$rawValue"/>				
					</xsl:when>				
					<!-- shared string -->
					<xsl:when test="$rawType = 's'">
						<xsl:variable name="sharedStringText">
							<xsl:value-of 
								select="
									document(
										$sharedStringsFilePath
									)/main:sst/main:si[position() = current()/main:v + 1]/main:t
								"/>
						</xsl:variable>						
						<xsl:choose>				
							<xsl:when test="$sharedStringText != ''">
								<xsl:value-of select="$sharedStringText"/>				
							</xsl:when>				
							<xsl:otherwise>
								<!-- rich text -->
								<xsl:value-of 
									select="
										string-join(
											document(
												$sharedStringsFilePath
											)/main:sst/main:si[position() = current()/main:v + 1]/main:r/main:t,
											''
										)
									"/>				
							</xsl:otherwise>				
						</xsl:choose>							
					</xsl:when>				
					<!-- inline string -->
					<xsl:when test="$rawType = 'inlineStr'">
						<xsl:value-of select="./main:is/main:t"/>				
					</xsl:when>				
					<!-- date -->
					<xsl:when test="$type = 'd'">
						<xsl:if test="$rawValue">
							<xsl:variable name="nDays" select="floor(number($rawValue))"/>
							<xsl:variable name="nTime" select="$rawValue - $nDays"/>
							<xsl:variable name="nHours" select="floor($nTime * 24)"/>
							<xsl:variable name="nMinutes" select="floor($nTime * 1440) - ($nHours * 60)"/>
							<xsl:variable name="nSeconds" select="floor($nTime * 86400) - ($nHours * 3600) - ($nMinutes * 60)"/>
							<xsl:variable name="dayTimeDuration" 
								select="
									xs:dayTimeDuration(
										concat(
											'P', 
											$nDays, 
											'DT',
											$nHours,
											'H',
											$nMinutes ,
											'M',
											$nSeconds,
											'S'
										)
									)
								"/>
							<xsl:choose>				
								<xsl:when test="$local:date1904 = 'false'">
									<xsl:value-of select="xs:dateTime('1900-03-01T00:00:00') - xs:dayTimeDuration('P61D') + $dayTimeDuration"/>				
								</xsl:when>							
								<xsl:otherwise>
									<xsl:value-of select="xs:dateTime('1904-01-01T00:00:00') + $dayTimeDuration"/>				
								</xsl:otherwise>
							</xsl:choose>				
						</xsl:if>
					</xsl:when>				
					<xsl:otherwise>
						<xsl:value-of select="$rawValue"/>				
					</xsl:otherwise>				
				</xsl:choose>	
			</xsl:variable>
			<xsl:call-template name="DSValue">
				<!-- value -->
				<xsl:with-param name="value" select="$value" />
				<xsl:with-param name="isLastField" select="'true'" />
			</xsl:call-template>			
				
			<xsl:value-of select="$lineBreak"/>
			
		</xsl:for-each>
	
	</xsl:template>

	<xsl:template name="DSValue">
		<xsl:param name="value"/>  
		<xsl:param name="isLastField" select="'false'"/>  
		
		<xsl:choose>
			<xsl:when test="contains($value, $quotationMark)">
				<xsl:value-of select="concat($quotationMark, replace($value, $quotationMark, concat($quotationMark, $quotationMark)), $quotationMark)"/>
			</xsl:when>
			<xsl:when test="contains($value, $delimiter) or contains($value, $lineBreak)">
				<xsl:value-of select="concat($quotationMark, $value, $quotationMark)"/>
			</xsl:when>
			<xsl:otherwise>
				<xsl:value-of select="$value"/>
			</xsl:otherwise>
		</xsl:choose>
	
		<xsl:if test="$isLastField = 'false'">
			<xsl:value-of select="$delimiter"/>
		</xsl:if>		
	</xsl:template>
	
	<xsl:template name="alpha2Number">
		<xsl:param name="string"/>  
		<xsl:param name="alpha" select="'ABCDEFGHIJKLMNOPQRSTUVWXYZ'"/> 
		<xsl:param name="magnitude" select="1"/>
		<xsl:param name="carryover" select="0"/>
		<xsl:param name="bit" select="substring($string, string-length($string), 1)"/>  
		<xsl:param name="bit-value" select="string-length(substring-before($alpha, $bit)) + 1"/>
		<xsl:variable name="return" select="$carryover + $bit-value * $magnitude"/>
		<xsl:choose>
			<xsl:when test="string-length($string) > 1">
				<xsl:call-template name="alpha2Number">
					<xsl:with-param name="string" select="substring($string, 1, string-length($string) - 1)"/>
					<xsl:with-param name="magnitude" select="string-length($alpha) * $magnitude"/>
					<xsl:with-param name="carryover" select="$return"/>
				</xsl:call-template>
			</xsl:when>
			<xsl:otherwise>
				<xsl:value-of select="$return" />
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	
	<xsl:template name="parentDirectory">
		<xsl:param name="filePath"/>
		<xsl:value-of select="replace($filePath, '[\\/]([^\\/]+)$', '')"/>
	</xsl:template>	
		
</xsl:stylesheet>