import unittest
import tempfile
import json
from pathlib import Path
from unittest.mock import patch
from audit_pub import audit, main


class AuditTests(unittest.TestCase):
    def inventory(self):
        return {'packages':[{'name':'first','version':'1.0.0','source':'hosted'},{'name':'second','version':'2.0.0','source':'hosted'},{'name':'flutter','version':'0.0.0','source':'sdk'}]}

    def test_partial_pagination_keeps_findings_with_the_correct_package(self):
        calls=[]
        def send(queries):
            calls.append(queries)
            if len(calls)==1:return {'results':[{}, {'next_page_token':'next'}]}
            return {'results':[{'vulns':[{'id':'TEST-ADVISORY'},{'id':'TEST-ADVISORY'}]}]}
        result=audit(self.inventory(),send)
        self.assertEqual(result['packages'][0]['vulnerabilities'],[])
        self.assertEqual(result['packages'][1]['vulnerabilities'],['TEST-ADVISORY'])
        self.assertEqual(calls[1],[{'package':{'name':'second','ecosystem':'Pub'},'version':'2.0.0','page_token':'next'}])
        self.assertEqual(result['excluded'],[{'name':'flutter','source':'sdk'}])

    def test_incomplete_error_or_endless_responses_do_not_pass(self):
        for response in ({},{'results':[{}]},{'results':[{}, {'error':'TEST'}]},{'results':[{'next_page_token':'endless'},{'next_page_token':'endless'}]}):
            with self.assertRaises(ValueError):audit(self.inventory(),lambda _:response)
        with self.assertRaises(ValueError):audit({'packages':[]})
        with self.assertRaises(ValueError):audit({'packages':[{'name':'private','source':'git'}]})

    def test_private_host_is_rejected_before_any_advisory_query(self):
        with tempfile.TemporaryDirectory() as root:
            root=Path(root);inventory=root/'inventory.json';lock=root/'pubspec.lock'
            inventory.write_text(json.dumps(self.inventory()),encoding='utf-8')
            lock.write_text('      url: "https://pub.dev"\n      url: "https://private.example"\n',encoding='utf-8')
            with patch('sys.argv',['audit_pub',str(inventory),'--lock',str(lock),'--output',str(root/'report.json')]),patch('audit_pub.audit',side_effect=AssertionError('must not query')):
                with self.assertRaisesRegex(ValueError,'public pub.dev'):main()


if __name__=='__main__':unittest.main()
