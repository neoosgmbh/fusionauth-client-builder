[#import "_macros.ftl" as global/]
/*
* Copyright (c) 2019, FusionAuth, All Rights Reserved
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*   http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing,
* software distributed under the License is distributed on an
* "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
* either express or implied. See the License for the specific
* language governing permissions and limitations under the License.
*/

package client

import (
  "bytes"
  "encoding/base64"
  "encoding/json"
  "errors"
  "fmt"
  "io"
  "net/http"
  "net/http/httputil"
  "net/url"
  "strconv"
  "strings"
)

var ErrRequestUnsuccessful = errors.New("Response from FusionAuth API was not successful")

// URIWithSegment returns a string with a "/" delimiter between the uri and segment
// If segment is not set (""), just the uri is returned
func URIWithSegment(uri, segment string) string {
	if segment == "" {
		return uri
	}
	return uri + "/" + segment
}

// NewRequest creates a new request for the FusionAuth API call
func (c *FusionAuthClient) NewRequest(method, endpoint string, body interface{}) (*http.Request, error) {
	rel := &url.URL{Path: endpoint}
	u := c.BaseURL.ResolveReference(rel)
	var buf io.ReadWriter
	if body != nil {
		buf = new(bytes.Buffer)
		err := json.NewEncoder(buf).Encode(body)
		if err != nil {
			return nil, err
		}
	}
	req, err := http.NewRequest(method, u.String(), buf)
	if err != nil {
		return nil, err
	}
	if c.APIKey != "" {
		// Send the API Key, but only if it is set
		req.Header.Set("Authorization", c.APIKey)
	}
	req.Header.Set("Accept", "application/json")
	return req, nil
}

// Do makes the request to the FusionAuth API endpoint and decodes the response
func (c *FusionAuthClient) Do(req *http.Request, v interface{}) (*http.Response, error) {
	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	responseDump, _ := httputil.DumpResponse(resp, true)
	fmt.Println(string(responseDump))
	err = json.NewDecoder(resp.Body).Decode(v)
	if err == nil && (resp.StatusCode < 200 || resp.StatusCode > 299) {
		// If everything went well but the API responded with something other than HTTP 2xx, we raise an error
		// That way, consumers can check for ErrRequestUnsuccessful
		return resp, ErrRequestUnsuccessful
	}
	return resp, err
}

// FusionAuthClient describes the Go Client for interacting with FusionAuth's RESTful API
type FusionAuthClient struct {
	BaseURL    *url.URL
	APIKey     string
	HTTPClient *http.Client
}

[#-- @formatter:off --]
[#list apis as api]
// ${api.methodName?cap_first}
  [#list api.comments as comment]
// ${comment}
  [/#list]
  [#list api.params![] as param]
    [#if !param.constant??]
//   ${global.optional(param, "go")}${global.convertType(param.javaType, "go")} ${param.name} ${param.comments?join("\n//   ")}
    [/#if]
  [/#list]
  [#assign parameters = global.methodParameters(api, "go")/]
func (c *FusionAuthClient) ${api.methodName?cap_first}(${parameters}) (interface{}, error) {
    var body interface{}
    uri := "${api.uri}"
    method := http.Method${api.method?capitalize}
  [#list api.params![] as param]
    [#if param.type == "urlSegment"]
      [#if !param.constant?? && param.javaType == "Integer"]
    uri = URIWithSegment(uri, string(${(param.constant?? && param.constant)?then(param.value, param.name)}))
      [#else]
    uri = URIWithSegment(uri, ${(param.constant?? && param.constant)?then(param.value, param.name)})
      [/#if]
    [#elseif param.type == "body"]
    body = ${param.name}
    [/#if]
  [/#list]
    req, err := c.NewRequest(method, uri, body)
  [#list api.params![] as param]
    [#if param.type == "urlParameter"]
    q := req.URL.Query()
      [#break]
    [/#if]
  [/#list]
  [#list api.params![] as param]
    [#if param.type == "urlParameter"]
      [#if param.value?? && param.value == "true"]
    q.Add("${param.parameterName}", strconv.FormatBool(true))
      [#elseif param.value?? && param.value == "false"]
    q.Add("${param.parameterName}", strconv.FormatBool(false))
      [#elseif !param.constant?? && param.javaType == "boolean"]
    q.Add("${param.parameterName}", strconv.FormatBool(${(param.constant?? && param.constant)?then(param.value, param.name)}))
      [#elseif !param.constant?? && global.convertType(param.javaType, "go") == "[]string"]
    for _, ${param.parameterName} := range ${(param.constant?? && param.constant)?then(param.value, param.name)} {
 		  q.Add("${param.parameterName}", ${param.parameterName})
 	  }
      [#elseif !param.constant?? && global.convertType(param.javaType, "go") == "interface{}"]
    q.Add("${param.parameterName}", ${(param.constant?? && param.constant)?then(param.value, (param.name == "type")?then("_type", param.name))}.(string))
      [#else]
    q.Add("${param.parameterName}", string(${(param.constant?? && param.constant)?then(param.value, param.name)}))
      [/#if]
    [#elseif param.type == "body"]
    req.Header.Set("Content-Type", "application/json")
    [/#if]
  [/#list]
  [#if api.method == "post" && !global.hasBodyParam(api.params![])]
    req.Header.Set("Content-Type", "text/plain")
  [/#if]
  [#if api.authorization??]
    req.Header.Set("Authorization", ${api.authorization})
  [/#if]
    var resp interface{}
    _, err = c.Do(req, &resp)
    return resp, err
}

[/#list]
[#-- @formatter:on --]


// ExchangeOAuthCodeForAccessToken
// Exchanges an OAuth authorization code for an access token.
//   string code The OAuth authorization code.
//   string clientID The OAuth client_id.
//   string clientSecret (Optional: use "" to disregard this parameter) The OAuth client_secret used for Basic Auth.
//   string redirectURI The OAuth redirect_uri.
func (c *FusionAuthClient) ExchangeOAuthCodeForAccessToken(code string, clientID string, clientSecret string, redirectURI string) (interface{}, error) {
  // URL
  rel := &url.URL{Path: "/oauth2/token"}
  u := c.BaseURL.ResolveReference(rel)
  // Body
  body := url.Values{}
  body.Set("code", code)
  body.Set("grant_type", "authorization_code")
  body.Set("client_id", clientID)
  body.Set("redirect_uri", redirectURI)
  encodedBody := strings.NewReader(body.Encode())
  // Request
  method := http.MethodPost
  req, err := http.NewRequest(method, u.String(), encodedBody)
  req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
  // Basic Auth (optional)
  if clientSecret != "" {
    credentials := clientID + ":" + clientSecret
    encoded := base64.StdEncoding.EncodeToString([]byte(credentials))
    req.Header.Set("Authorization", "Basic " + encoded)
  }
  var resp interface{}
  _, err = c.Do(req, &resp)
  return resp, err
}
